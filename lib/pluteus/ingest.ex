defmodule Pluteus.Ingest do
  @moduledoc """
  The path from a file appearing in the inbox to a holding (spec-04).

  Each stage finds its work by querying recorded state for what lacks its
  output and has no uncleared finding against it. The job queue only schedules
  the stages; emptying it loses nothing, because nothing here is known only to
  a job.

  Acquisition follows §4.3's order: the record is written, with the identifier
  and the location derived from it, before any byte moves. Every interruption
  therefore leaves a record the next pass finds and completes, and the
  deployment never removes an inbox file that no record accounts for.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Catalog.Asset
  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Ingest.Category
  alias Pluteus.Ingest.Finding
  alias Pluteus.Ingest.Identify
  alias Pluteus.Ingest.Registry
  alias Pluteus.Ingest.Sighting
  alias Pluteus.Lifecycle
  alias Pluteus.PlatformEvents
  alias Pluteus.Principals
  alias Pluteus.Repo
  alias Pluteus.Storage

  @layout ~r|\A[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z|

  @doc """
  The one inbox the household writes to (spec-04 §4.1).

  There is exactly one, and the model is built on it. `inbox_sightings` is keyed on the
  path relative to it, and `acquisitions` admits one in-progress acquisition per relative
  path, so a relative path identifies a file across the whole deployment — which is also
  why an acquisition survives the inbox being mounted somewhere else. A second watched
  directory could not be told from the first, and `Pluteus.Ingest.AcquisitionTest` asserts
  the two keys that say so.

  `acquire/2` and `Pluteus.Ingest.Place.place_due/1` are given an inbox rather than
  reading it here, so that a test can work in a directory of its own. Both of those
  arguments name this one in the deployment, and each takes the inbox only to read the
  filesystem: which acquisitions they consider is not narrowed by it, because under one
  inbox there is nothing to narrow.
  """
  @spec inbox() :: Path.t()
  def inbox, do: config(:inbox)

  @doc """
  One pass of the acquire stage over an inbox.

  In-progress records are completed first, whatever state their inbox file is
  in. The inbox is then walked for files not yet acquired.

  Options:

    * `:now` — the moment of the pass, against which settling is measured.
    * `:settle_seconds` — how long a file must be seen unchanged.

  Returns what the pass did with every file it looked at.
  """
  @spec acquire(Path.t(), keyword()) :: map()
  def acquire(inbox, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    settle = Keyword.get_lazy(opts, :settle_seconds, fn -> config(:settle_seconds) end)

    recovered = Enum.map(in_progress(), &recover(&1, inbox, now))
    %{candidates: candidates, held_back: held_back} = walk(inbox)

    outcomes =
      Enum.map(candidates, fn {relative, stat} ->
        {relative, acquire_file(inbox, relative, stat, now, settle)}
      end)

    %{recovered: recovered, files: outcomes, held_back: held_back}
  end

  @doc """
  What the inbox is holding back and why: operating-system metadata, downloads
  in progress, symbolic links and anything that is not a regular file. None of
  it is acquired and none of it is removed (§4.1).
  """
  @spec held_back(Path.t()) :: [{String.t(), atom()}]
  def held_back(inbox), do: walk(inbox).held_back

  @doc """
  One pass of the identify stage: every stored acquisition not yet identified
  and with no uncleared finding at this stage.
  """
  @spec identify_due() :: [{Ecto.UUID.t(), :identified | :finding}]
  def identify_due do
    blocked =
      from f in Finding,
        where: f.stage == :identify and is_nil(f.cleared_at),
        select: f.acquisition_id

    from(a in Acquisition, where: a.state == :stored, where: a.id not in subquery(blocked))
    |> Repo.all()
    |> Enum.map(&{&1.id, identify(&1)})
  end

  @doc """
  Records a finding for every file under primary storage laid out as an
  acquisition's bytes that neither an acquisition nor an asset has as its
  location. §4.3's order cannot produce one, so each is a surprise, and nothing
  is deleted.
  """
  @spec find_stray_bytes(DateTime.t()) :: non_neg_integer()
  def find_stray_bytes(now \\ DateTime.utc_now()) do
    found = laid_out(Storage.root())

    accounted =
      MapSet.new(
        Repo.all(from(a in Acquisition, where: a.location in ^found, select: a.location)) ++
          Repo.all(from(a in Asset, where: a.location in ^found, select: a.location))
      )

    stray = Enum.reject(found, &MapSet.member?(accounted, &1))

    rows =
      Enum.map(stray, fn location ->
        %{
          id: UUIDv7.generate(),
          stage: :acquire,
          kind: "bytes_without_a_record",
          permanent: true,
          detail: %{},
          location: location,
          recorded_at: now,
          inserted_at: now,
          updated_at: now
        }
      end)

    record_stray(rows)
  end

  # In batches, because the wire protocol carries at most 65535 parameters in one
  # statement and a finding spends nine of them. A single insert therefore fails
  # outright somewhere past seven thousand stray files — and a deployment that has
  # that many is exactly one whose operator needs the report, so the pass would
  # crash every night for the reason it was most needed.
  @per_statement 1_000

  defp record_stray(rows) do
    rows
    |> Enum.chunk_every(@per_statement)
    |> Enum.reduce(0, fn batch, recorded ->
      {count, _} =
        Repo.insert_all(Finding, batch,
          on_conflict: :nothing,
          conflict_target:
            {:unsafe_fragment, "(location) WHERE location IS NOT NULL AND cleared_at IS NULL"}
        )

      recorded + count
    end)
  end

  @doc """
  The location an identifier's bytes lie at (§4.5). It derives from the
  identifier alone: renaming, re-placing or re-identifying a holding never
  moves them. The two directory levels come from the identifier's random tail,
  since its leading digits are a timestamp and would put a day's files in one
  directory.
  """
  @spec location_for(Ecto.UUID.t()) :: String.t()
  def location_for(id) do
    hex = String.replace(id, "-", "")
    "#{String.slice(hex, -2, 2)}/#{String.slice(hex, -4, 2)}/#{id}"
  end

  @doc """
  Every uncleared finding.
  """
  @spec open_findings() :: [Finding.t()]
  def open_findings,
    do: Repo.all(from f in Finding, where: is_nil(f.cleared_at), order_by: f.recorded_at)

  @doc """
  How many findings are uncleared.

  A finding is the household's, not a principal's, so this is a household figure and the
  chrome may carry it on every surface.
  """
  @spec open_finding_count() :: non_neg_integer()
  def open_finding_count,
    do: Repo.aggregate(from(f in Finding, where: is_nil(f.cleared_at)), :count)

  @doc """
  Every uncleared finding recorded against one input.

  What a surface reads to tell a derivative nobody has made yet from one a tool tried
  to make and could not: §11.6 answers both absences alike, and §5.2 keeps them apart.
  """
  @spec open_findings_for_input(Ecto.UUID.t()) :: [Finding.t()]
  def open_findings_for_input(input_id) do
    Repo.all(
      from f in Finding,
        where: f.input_id == ^input_id and is_nil(f.cleared_at),
        order_by: f.recorded_at
    )
  end

  @spec findings_for_acquisition(Ecto.UUID.t()) :: [Finding.t()]
  def findings_for_acquisition(acquisition_id) do
    Repo.all(
      from f in Finding, where: f.acquisition_id == ^acquisition_id, order_by: f.recorded_at
    )
  end

  @doc """
  Clears a finding, asking for its subject to be tried again. The finding stays
  on record with who cleared it.
  """
  @spec clear_finding(Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) ::
          {:ok, Finding.t()} | {:error, Ecto.Changeset.t()}
  def clear_finding(finding_id, principal_id, now \\ DateTime.utc_now()) do
    Finding
    |> Repo.get!(finding_id)
    |> Finding.clear_changeset(principal_id, now)
    |> Repo.update()
  end

  @doc """
  Runs one item's work for a stage. An exception is recorded as a finding
  against the item, with the exception and where it was raised, and returned
  as `{:crashed, message}`, so one item that cannot be handled neither stops a
  pass over the others nor comes due again until a person clears it. The
  caller reports the crash in its own result, which fails the pass's job.
  """
  @spec isolated(atom(), map(), (-> result)) :: result | {:crashed, String.t()}
        when result: term()
  def isolated(stage, subject, fun) do
    fun.()
  rescue
    exception ->
      message = Exception.format(:error, exception, __STACKTRACE__)

      record_finding(
        Map.merge(subject, %{
          stage: stage,
          kind: "crashed",
          permanent: false,
          detail: %{exception: message}
        })
      )

      {:crashed, message}
  end

  @doc """
  Whether any outcome in a pass is a crash.
  """
  @spec crashed?(Enumerable.t()) :: boolean()
  def crashed?(outcomes), do: Enum.any?(outcomes, &match?({_item, {:crashed, _}}, &1))

  @spec record_finding(map()) :: Finding.t()
  def record_finding(attrs) do
    attrs = Map.put_new(attrs, :recorded_at, DateTime.utc_now())
    %Finding{} |> Finding.changeset(attrs) |> Repo.insert!()
  end

  @spec get_acquisition!(Ecto.UUID.t()) :: Acquisition.t()
  def get_acquisition!(id), do: Repo.get!(Acquisition, id)

  @spec acquisitions_from(String.t()) :: [Acquisition.t()]
  def acquisitions_from(inbox_path) do
    Repo.all(from a in Acquisition, where: a.inbox_path == ^inbox_path, order_by: a.id)
  end

  # --- Walking the inbox ------------------------------------------------------

  defp walk(inbox), do: walk(inbox, "", %{candidates: [], held_back: []})

  defp walk(inbox, relative_dir, acc) do
    inbox
    |> Path.join(relative_dir)
    |> File.ls!()
    |> Enum.sort()
    |> Enum.reduce(acc, fn name, acc ->
      relative = if relative_dir == "", do: name, else: Path.join(relative_dir, name)
      visit(inbox, relative, File.lstat!(Path.join(inbox, relative), time: :posix), acc)
    end)
  end

  defp visit(_inbox, relative, %File.Stat{type: :symlink}, acc),
    do: hold_back(acc, relative, :symbolic_link)

  defp visit(inbox, relative, %File.Stat{type: :directory}, acc) do
    if Registry.ignored?(Path.join(relative, "_")),
      do: hold_back(acc, relative, :ignored),
      else: walk(inbox, relative, acc)
  end

  defp visit(_inbox, relative, %File.Stat{type: :regular} = stat, acc) do
    if Registry.ignored?(relative),
      do: hold_back(acc, relative, :ignored),
      else: %{acc | candidates: acc.candidates ++ [{relative, stat}]}
  end

  defp visit(_inbox, relative, %File.Stat{}, acc),
    do: hold_back(acc, relative, :not_a_regular_file)

  defp hold_back(acc, relative, reason),
    do: %{acc | held_back: acc.held_back ++ [{relative, reason}]}

  # --- One file -----------------------------------------------------------------

  defp acquire_file(inbox, relative, stat, now, settle) do
    source = Path.join(inbox, relative)

    cond do
      not settled?(relative, stat, now, settle) ->
        :unsettled

      # A file the deployment has looked at and not taken keeps the record it was looked
      # at under, and this pass has already recovered it. Acquiring it again would be a
      # second record of one file in the inbox, which the index refuses.
      in_progress?(relative) ->
        :in_progress

      already_acquired?(relative, source) ->
        :ok = File.rm(source)
        Repo.delete_all(from s in Sighting, where: s.inbox_path == ^relative)
        :already_acquired

      true ->
        acquire_new(inbox, source, relative, stat)
    end
  end

  defp in_progress?(relative) do
    Repo.exists?(
      from a in Acquisition,
        where: a.inbox_path == ^relative and is_nil(a.inbox_released_at)
    )
  end

  defp settled?(relative, stat, now, settle) do
    case Repo.get(Sighting, relative) do
      %Sighting{size: size, mtime: mtime, seen_at: seen_at}
      when size == stat.size and mtime == stat.mtime ->
        DateTime.diff(now, seen_at, :second) >= settle

      _changed_or_unseen ->
        Repo.insert!(
          %Sighting{inbox_path: relative, size: stat.size, mtime: stat.mtime, seen_at: now},
          on_conflict: {:replace, [:size, :mtime, :seen_at]},
          conflict_target: :inbox_path
        )

        false
    end
  end

  # §4.4: the same bytes dropped again at the same path, while what they became
  # is still held, are already acquired. Once that holding is recycled or
  # purged, the household is bringing back something it deleted.
  # A file that cannot be read cannot be judged the same as anything. It is
  # acquired like any other, so that its failure is recorded against a record
  # (§9) rather than raised before one exists.
  defp already_acquired?(relative, source) do
    case Storage.digest_file(source, :sha256) do
      {:ok, digest} ->
        from(a in Acquisition,
          where: a.inbox_path == ^relative and a.digest == ^digest,
          where: a.state in [:stored, :identified, :placed]
        )
        |> Repo.all()
        |> Enum.any?(&holding_live?/1)

      {:error, _unreadable} ->
        false
    end
  end

  defp holding_live?(%Acquisition{state: :placed, digital_item_id: digital_item_id}),
    do: match?({:live, _}, Lifecycle.state(digital_item_id))

  defp holding_live?(%Acquisition{}), do: true

  defp acquire_new(inbox, source, relative, stat) do
    id = UUIDv7.generate()

    acquisition =
      %{id: id, inbox_path: relative, location: location_for(id)}
      |> Acquisition.recorded_changeset()
      |> Repo.insert!()

    Repo.delete_all(from s in Sighting, where: s.inbox_path == ^relative)

    # spec-01 §11.2's platform class, and §11.1's "a file arriving". Announced here
    # rather than at placement, so a file that never identifies is still an arrival
    # the household saw; its subject is the acquisition, there being nothing
    # catalogued yet to name. Attributed to the System principal explicitly, because
    # acquisition sets no actor — it writes no catalog row.
    {:ok, _event} =
      PlatformEvents.record("acquired", {:acquisition, acquisition.id}, Principals.system!().id)

    {:acquired,
     isolated(:acquire, %{acquisition_id: acquisition.id}, fn ->
       examine(inbox, acquisition, source, stat)
     end)
     |> tag_crash(acquisition.id)}
  end

  # §4.3 and §6.3. The deployment takes a file only when it can say what it is, so what it
  # is is decided where the file lies: in the inbox, beside the documents that say so, and
  # before anything is moved anywhere.
  #
  # A file nothing says the category of stays where the household put it. There it can be
  # dealt with the way a person deals with files — a document put beside it, a move into a
  # directory that says what it is — and the next pass takes it. Taking it first and
  # guessing would put it where only this deployment can find it, under a category nobody
  # chose and nothing can tell from one that was.
  defp examine(inbox, acquisition, source, stat, take \\ &place_bytes/4) do
    case read_bytes(acquisition, source) do
      {:ok, identified} ->
        decide(inbox, acquisition, source, stat, identified, take)

      {:error, {kind, detail}} ->
        undecided(acquisition, kind, detail)
    end
  end

  # What a previous pass read, where there was one. The file is settled and this is the
  # record of that same file, so what the bytes are is what that pass said; what is looked
  # at again is the evidence around them, which is what a person changes.
  defp read_bytes(%Acquisition{format: format} = acquisition, _source) when is_binary(format),
    do: {:ok, Map.take(acquisition, Acquisition.read_fields())}

  defp read_bytes(acquisition, source) do
    with {:ok, identified} <- Identify.identify(acquisition, source) do
      acquisition |> Acquisition.examined_changeset(identified) |> Repo.update!()

      {:ok, identified}
    end
  end

  defp decide(inbox, acquisition, source, stat, identified, take) do
    case Category.decide(identified, inbox, acquisition.inbox_path) do
      %{category: nil} ->
        undecided(acquisition, "category_undecided", %{
          format: identified.format,
          media_class: to_string(identified.media_class)
        })

      decided ->
        take.(acquisition, source, stat, Map.merge(identified, decided))
    end
  end

  # The bytes were taken and the crash came before anything was recorded about them. The
  # file is gone from the inbox, so the documents that were beside it may be gone too:
  # what can be decided is decided, and what cannot is a finding against bytes the
  # deployment now holds and cannot say the category of. Nothing retries it, because
  # nothing about it will change on its own.
  defp taken_already(acquisition, inbox) do
    stored = acquisition |> release() |> measure()

    with {:ok, identified} <- Identify.identify(stored),
         %{category: category} = decided when not is_nil(category) <-
           Category.decide(identified, inbox, stored.inbox_path) do
      recorded(stored, Map.merge(identified, decided))
    else
      {:error, {kind, detail}} -> undecided(stored, kind, detail)
      %{category: nil} -> undecided(stored, "category_undecided", %{})
    end
  end

  # Nothing says what the file is, so the deployment does not take it: it stays where the
  # household put it and the finding says why. The finding is not permanent — a document
  # put beside the file, or a move into a directory that says what it is, is what answers
  # it, and the next pass reads that.
  defp undecided(acquisition, kind, detail) do
    record_finding(%{
      stage: :examine,
      kind: kind,
      permanent: false,
      detail: detail,
      acquisition_id: acquisition.id
    })

    {acquisition.id, :undecided}
  end

  defp tag_crash({:crashed, message}, id), do: {id, {:crashed, message}}
  defp tag_crash(outcome, _id), do: outcome

  # A file with another hard link is copied: renaming it would leave the bytes
  # reachable, and changeable, through the other link. A rename across file
  # systems is a copy too.
  defp place_bytes(acquisition, source, %File.Stat{links: links}, examined) when links > 1,
    do: copy_bytes(acquisition, source, examined)

  defp place_bytes(acquisition, source, _stat, examined) do
    case Storage.rename_in(source, acquisition.location) do
      :ok ->
        acquisition |> release() |> measure() |> recorded(examined)

      {:error, :exdev} ->
        copy_bytes(acquisition, source, examined)
    end
  end

  defp copy_bytes(acquisition, source, examined) do
    :ok = Storage.copy_in(source, acquisition.location)
    finish_copy(acquisition, source, examined)
  end

  # The copy is compared with its source before the source is removed. A copy
  # that differs is a surprise and raises; the record stays in progress and the
  # next pass copies again.
  defp finish_copy(acquisition, source, examined) do
    {:ok, at_source} = Storage.digest_file(source, :sha256)
    {:ok, copied} = Storage.digest(acquisition.location, :sha256)

    if at_source != copied do
      raise "copy of #{acquisition.inbox_path} to #{acquisition.location} differs from its source"
    end

    stored = measure(acquisition)
    outcome = recorded(stored, examined)
    :ok = File.rm(source)
    release(Repo.get!(Acquisition, stored.id))
    outcome
  end

  # What examination read, written once the bytes are the deployment's. The file is gone
  # from the inbox by now, so nothing here reads it again: identification and the category
  # were both decided while it was still there.
  defp recorded(%Acquisition{state: :stored} = acquisition, examined) do
    acquisition |> Acquisition.identified_changeset(examined) |> Repo.update!()

    {acquisition.id, :identified}
  end

  defp recorded(acquisition, _examined), do: {acquisition.id, acquisition.state}

  defp release(acquisition) do
    acquisition
    |> Ecto.Changeset.change(inbox_released_at: DateTime.utc_now())
    |> Repo.update!()
  end

  defp measure(%Acquisition{state: :recorded} = acquisition) do
    {:ok, measured} = Storage.measure(acquisition.location)
    acquisition |> Acquisition.stored_changeset(measured) |> Repo.update!()
  end

  defp measure(acquisition), do: acquisition

  defp identify(acquisition) do
    isolated(:identify, %{acquisition_id: acquisition.id}, fn -> identify_now(acquisition) end)
  end

  defp identify_now(acquisition) do
    case Identify.identify(acquisition) do
      {:ok, identified} ->
        acquisition |> Acquisition.identified_changeset(identified) |> Repo.update!()
        :identified

      {:error, {kind, detail}} ->
        record_finding(%{
          stage: :identify,
          kind: kind,
          permanent: true,
          detail: detail,
          acquisition_id: acquisition.id
        })

        :finding
    end
  end

  # --- Recovery (§4.3) ------------------------------------------------------------

  defp in_progress do
    blocked =
      from f in Finding,
        where: f.stage == :acquire and is_nil(f.cleared_at) and not is_nil(f.acquisition_id),
        select: f.acquisition_id

    Repo.all(
      from a in Acquisition,
        where: is_nil(a.inbox_released_at),
        where: a.id not in subquery(blocked),
        order_by: a.id
    )
  end

  defp recover(acquisition, inbox, now) do
    {acquisition.id,
     isolated(:acquire, %{acquisition_id: acquisition.id}, fn ->
       recover_now(acquisition, inbox, now)
     end)}
  end

  defp recover_now(acquisition, inbox, now) do
    source = Path.join(inbox, acquisition.inbox_path)
    at_source = match?({:ok, %File.Stat{type: :regular}}, File.lstat(source))
    at_location = Storage.exists?(acquisition.location)

    outcome =
      case {at_source, at_location} do
        {true, false} ->
          examine(inbox, acquisition, source, File.stat!(source))

        {true, true} ->
          examine(inbox, acquisition, source, File.stat!(source), &resume_copy/4)

        {false, true} ->
          taken_already(acquisition, inbox)

        {false, false} ->
          vanished(acquisition, now)
      end

    case outcome do
      {_id, result} -> result
      result -> result
    end
  end

  defp resume_copy(acquisition, source, _stat, examined) do
    {:ok, at_source} = Storage.digest_file(source, :sha256)
    {:ok, copied} = Storage.digest(acquisition.location, :sha256)

    if at_source == copied do
      finish_copy(acquisition, source, examined)
    else
      :ok = Storage.delete(acquisition.location)
      copy_bytes(acquisition, source, examined)
    end
  end

  defp vanished(acquisition, now) do
    acquisition
    |> Ecto.Changeset.change(state: :vanished, inbox_released_at: now)
    |> Repo.update!()

    record_finding(%{
      stage: :acquire,
      kind: "inbox_file_left_before_it_moved",
      permanent: true,
      acquisition_id: acquisition.id,
      recorded_at: now
    })

    :vanished
  end

  defp laid_out(root) do
    case File.ls(root) do
      {:ok, _} ->
        root
        |> Path.join("*/*/*")
        |> Path.wildcard(match_dot: false)
        |> Enum.map(&Path.relative_to(&1, root))
        |> Enum.filter(&Regex.match?(@layout, &1))

      {:error, :enoent} ->
        []
    end
  end

  defp config(key), do: :pluteus |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key)
end
