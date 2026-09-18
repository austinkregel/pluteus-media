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
  alias Pluteus.Ingest.Finding
  alias Pluteus.Ingest.Identify
  alias Pluteus.Ingest.Registry
  alias Pluteus.Ingest.Sighting
  alias Pluteus.Lifecycle
  alias Pluteus.Repo
  alias Pluteus.Storage

  @layout ~r|\A[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z|

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

    {count, _} =
      Repo.insert_all(Finding, rows,
        on_conflict: :nothing,
        conflict_target:
          {:unsafe_fragment, "(location) WHERE location IS NOT NULL AND cleared_at IS NULL"}
      )

    count
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

      already_acquired?(relative, source) ->
        :ok = File.rm(source)
        Repo.delete_all(from s in Sighting, where: s.inbox_path == ^relative)
        :already_acquired

      true ->
        acquire_new(source, relative, stat)
    end
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
  defp already_acquired?(relative, source) do
    {:ok, digest} = Storage.digest_file(source, :sha256)

    from(a in Acquisition,
      where: a.inbox_path == ^relative and a.digest == ^digest,
      where: a.state in [:stored, :identified, :placed]
    )
    |> Repo.all()
    |> Enum.any?(&holding_live?/1)
  end

  defp holding_live?(%Acquisition{state: :placed, digital_item_id: digital_item_id}),
    do: match?({:live, _}, Lifecycle.state(digital_item_id))

  defp holding_live?(%Acquisition{}), do: true

  defp acquire_new(source, relative, stat) do
    id = UUIDv7.generate()

    acquisition =
      %{id: id, inbox_path: relative, location: location_for(id)}
      |> Acquisition.recorded_changeset()
      |> Repo.insert!()

    Repo.delete_all(from s in Sighting, where: s.inbox_path == ^relative)

    {:acquired, place_bytes(acquisition, source, stat)}
  end

  # A file with another hard link is copied: renaming it would leave the bytes
  # reachable, and changeable, through the other link. A rename across file
  # systems is a copy too.
  defp place_bytes(acquisition, source, %File.Stat{links: links}) when links > 1,
    do: copy_bytes(acquisition, source)

  defp place_bytes(acquisition, source, _stat) do
    case Storage.rename_in(source, acquisition.location) do
      :ok ->
        acquisition |> release() |> measure() |> identify_and_report()

      {:error, :exdev} ->
        copy_bytes(acquisition, source)
    end
  end

  defp copy_bytes(acquisition, source) do
    :ok = Storage.copy_in(source, acquisition.location)
    finish_copy(acquisition, source)
  end

  # The copy is compared with its source before the source is removed. A copy
  # that differs is a surprise and raises; the record stays in progress and the
  # next pass copies again.
  defp finish_copy(acquisition, source) do
    {:ok, at_source} = Storage.digest_file(source, :sha256)
    {:ok, copied} = Storage.digest(acquisition.location, :sha256)

    if at_source != copied do
      raise "copy of #{acquisition.inbox_path} to #{acquisition.location} differs from its source"
    end

    stored = measure(acquisition)
    outcome = identify_and_report(stored)
    :ok = File.rm(source)
    release(Repo.get!(Acquisition, stored.id))
    outcome
  end

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

  defp identify_and_report(%Acquisition{state: :stored} = acquisition),
    do: {acquisition.id, identify(acquisition)}

  defp identify_and_report(acquisition), do: {acquisition.id, acquisition.state}

  defp identify(acquisition) do
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
    Repo.all(from a in Acquisition, where: is_nil(a.inbox_released_at), order_by: a.id)
  end

  defp recover(acquisition, inbox, now) do
    source = Path.join(inbox, acquisition.inbox_path)
    at_source = match?({:ok, %File.Stat{type: :regular}}, File.lstat(source))
    at_location = Storage.exists?(acquisition.location)

    outcome =
      case {at_source, at_location} do
        {true, false} ->
          place_bytes(acquisition, source, File.stat!(source))

        {true, true} ->
          resume_copy(acquisition, source)

        {false, true} ->
          acquisition |> release() |> measure() |> identify_and_report()

        {false, false} ->
          vanished(acquisition, now)
      end

    {acquisition.id, outcome}
  end

  defp resume_copy(acquisition, source) do
    {:ok, at_source} = Storage.digest_file(source, :sha256)
    {:ok, copied} = Storage.digest(acquisition.location, :sha256)

    if at_source == copied do
      finish_copy(acquisition, source)
    else
      :ok = Storage.delete(acquisition.location)
      copy_bytes(acquisition, source)
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
