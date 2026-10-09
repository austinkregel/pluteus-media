defmodule Pluteus.Playback do
  @moduledoc """
  What playing a holding acts on: the bytes, their type, and the region of them the
  holding is.

  §8.1 requires the primary action resolve to a specific expression and digital item
  without asking, and `Pluteus.Catalog.Selection` is what answers that. This is the step
  after it: the file a digital item holds, as the assets a client can be pointed at.

  ## A track of a release held in one file is a region, not a file

  spec-04 §6.4 records a track's extent within a single-file release as a temporal address
  against the manifestation carrying the bytes, linked to the track's own manifestation.
  So such a track has no digital item of its own and is reached the other way round: the
  address says which manifestation holds the bytes and which part of them the track is.

  Cutting that region into a file of its own is a transcode, which is why the OpenSubsonic
  surface refuses it. A media element is not: it is given the whole and told where to
  begin and end. The region is therefore the answer here rather than a reason to refuse,
  and nothing is re-encoded.

  ## A holding in several files is one sequence

  A reading in several parts is one digital item carrying an asset per part, and an
  address against it is against the whole reading rather than against any one part. So
  the parts are answered in order and a position is against the sequence, which is what
  lets a chapter address and a resume position mean the same thing.

  That only works where each part's own length is known, and a part's length comes from
  its own probe — which spec-04 §6.1 records against the asset whose bytes it read, so a
  part has one. A sequence with a part nothing measured is refused rather than answered
  with a position that cannot be placed in it.

  ## Nothing to play is an answer, not a failure

  A holding the household describes and holds no file for, and one whose bytes have not
  been normalized yet, both reach a surface as something it cannot act on. Each is named,
  because they are different facts and the second resolves itself.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Annotations
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.Addressing
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.AssetRole
  alias Pluteus.Catalog.Association
  alias Pluteus.Catalog.Cover
  alias Pluteus.Catalog.Credit
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Extent
  alias Pluteus.Catalog.Grouping
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Catalog.Selection
  alias Pluteus.Consumption
  alias Pluteus.Events
  alias Pluteus.Ingest.Place
  alias Pluteus.Ingest.Registry
  alias Pluteus.Ingest.Streams
  alias Pluteus.Lifecycle.RecycledRes
  alias Pluteus.Lifecycle.Tombstone
  alias Pluteus.Repo

  @typedoc """
  One file of a holding. `duration_ms` is nil only where the holding is one file, since
  a client playing one file reads its own length and a sequence cannot.
  """
  @type part :: %{
          asset_id: Ecto.UUID.t(),
          media_type: String.t(),
          duration_ms: non_neg_integer() | nil
        }

  @typedoc """
  What a client is pointed at. `from_ms` and `to_ms` are against the sequence the parts
  make, and are nil where the holding is the whole of what it is carried by.
  """
  @type playable :: %{
          parts: [part()],
          from_ms: non_neg_integer() | nil,
          to_ms: non_neg_integer() | nil
        }

  @typedoc """
  Why there is nothing to play.
  """
  @type refusal ::
          {:holds_no_file, Ecto.UUID.t()}
          | {:not_normalized, Ecto.UUID.t()}
          | {:sequence_unmeasured, Ecto.UUID.t()}

  @typedoc """
  One place in the queue as a surface shows it.
  """
  @type queued :: %{
          res_id: Ecto.UUID.t(),
          name: String.t(),
          queued_from: Ecto.UUID.t() | nil
        }

  @typedoc """
  What the transport is showing: the entry that is current, where in it the principal is,
  and the queue around it.

  `playable` carries the refusal rather than being absent where there is nothing to play,
  because §12.3's controls have to say why they cannot act rather than disappearing.
  """
  @type current :: %{
          res_id: Ecto.UUID.t(),
          name: String.t(),
          category: String.t() | nil,
          playable: {:ok, playable()} | {:error, refusal()},
          credited: [String.t()],
          cover: Ecto.UUID.t() | nil,
          position_ms: non_neg_integer(),
          extent_ms: non_neg_integer() | nil,
          index: non_neg_integer(),
          queue: [queued()]
        }

  @doc """
  What the transport shows for one principal, or nil where nothing is current.

  A saved queue with no current entry is not something playing: §12.3's queue outlives
  any one session, and a surface that drew a transport for it would claim a position in
  something nobody started.
  """
  @spec current(Ecto.UUID.t(), Profile.t()) :: current() | nil
  def current(principal_id, %Profile{} = profile) do
    case Consumption.play_queue(principal_id) do
      nil -> nil
      %{current_index: nil} -> nil
      queue -> showing(queue, profile)
    end
  end

  defp showing(queue, profile) do
    entries = Enum.sort_by(queue.entries, & &1.position)
    names = Resolution.visible_many(Enum.map(entries, & &1.res_id), profile)
    current = Enum.at(entries, queue.current_index)

    %{
      res_id: current.res_id,
      name: named(names, current.res_id, profile),
      category: Catalog.category_of(Catalog.work_of(current.res_id), Place.category_scheme()),
      playable: for_manifestation(current.res_id),
      credited: credited_for(current, profile),
      cover: Cover.for_manifestation(current.res_id, current.queued_from),
      position_ms: queue.position_ms,
      extent_ms: extent_ms(current.res_id),
      index: queue.current_index,
      queue:
        for entry <- entries do
          %{
            res_id: entry.res_id,
            name: named(names, entry.res_id, profile),
            queued_from: entry.queued_from
          }
        end
    }
  end

  # Who what is playing is by, which is the fact a person wants beside its name.
  #
  # A track crediting nobody is said to be by whoever its release is by: a container
  # names an album artist and leaves the track's own blank where they are the same
  # person, so taking the track's alone would leave most of a library anonymous.
  defp credited_for(entry, profile) do
    case credited(Catalog.work_of(entry.res_id), profile) do
      [] -> credited(entry.queued_from, profile)
      credited -> credited
    end
  end

  defp credited(nil, _profile), do: []

  defp credited(work_id, profile) do
    agents =
      Repo.all(
        from c in Credit,
          where: c.work_id == ^work_id,
          where: not is_nil(c.agent_id),
          order_by: [c.role, c.position],
          select: c.agent_id
      )

    named = agents |> Enum.uniq() |> Resolution.resolve_many(profile)

    agents |> Enum.map(&named[&1]) |> Enum.reject(&is_nil/1) |> Enum.map(& &1.nomen_string)
  end

  # The whole a position is measured along: spec-01 §8.4's recorded figure, which is the
  # same one §13.2's floor and ceiling are measured against. Taken from the parts instead
  # it would be nil for a holding carried by one file — a probe's duration is recorded on
  # the part only where there are parts — and the slider and the thresholds would be
  # measuring different things.
  defp extent_ms(res_id) do
    case Addressing.get_extent(res_id, :millisecond) do
      nil -> nil
      %Extent{magnitude: magnitude} -> magnitude
    end
  end

  # A queue entry naming a res nothing resolves a name for is a res this principal may
  # not see the name of, which is a queue entry nobody could have made. It is not a
  # blank row to draw.
  defp named(names, res_id, profile) do
    case names[res_id] do
      nil -> raise ArgumentError, "queued res #{res_id} resolves to no name this profile may see"
      nomens -> Resolution.choose(nomens, profile).nomen_string
    end
  end

  @doc """
  The queue playing a res fills, and which of its entries is the one asked for.

  Playing a grouping fills the queue with its members, and playing a member fills it with
  the grouping's members and starts at that one — so what follows a track is the rest of
  its release rather than nothing, which is also what makes §12.4's question answerable.
  A holding that is a member of nothing and carries no members is a queue of one.

  Each entry records the grouping it came in with, which §12.3 requires: a track reached
  from its release and the same track reached on its own are different queue entries, and
  only the record tells them apart.
  """
  @spec queue_for(Ecto.UUID.t(), Ecto.UUID.t(), Profile.t()) ::
          {[Consumption.entry()], non_neg_integer()}
  def queue_for(work_id, principal_id, %Profile{} = profile) do
    case Grouping.member_manifestations_of(work_id) do
      [] -> from_its_grouping(work_id, principal_id, profile)
      members -> {entries(members, work_id), 0}
    end
  end

  defp from_its_grouping(work_id, principal_id, profile) do
    case Grouping.grouping_of(work_id) do
      nil ->
        {[%{res_id: own_manifestation!(work_id, principal_id, profile), queued_from: nil}], 0}

      grouping ->
        members = Grouping.member_manifestations_of(grouping)
        mine = own_manifestation!(work_id, principal_id, profile)

        {entries(members, grouping), at(members, mine, grouping)}
    end
  end

  # The manifestation this work resolves to for this principal. A holding that is a
  # member of nothing is reached through §8.1's selection, which is where a work with
  # several expressions is decided between.
  defp own_manifestation!(work_id, principal_id, profile) do
    selected = Selection.for_principal(work_id, principal_id, profile)

    embodied_by(selected.expression.id) ||
      raise ArgumentError, "#{work_id} resolves to an expression embodying no manifestation"
  end

  # A grouping that does not carry the member it was reached through is a broken
  # relation, not a queue to start at the beginning of.
  defp at(members, manifestation_id, grouping) do
    Enum.find_index(members, &(&1 == manifestation_id)) ||
      raise ArgumentError,
            "#{manifestation_id} belongs to #{grouping}, which does not carry it as a member"
  end

  defp entries(members, queued_from) do
    for res_id <- members, do: %{res_id: res_id, queued_from: queued_from}
  end

  @doc """
  Starts a res playing on one device: fills the queue from it, makes its entry current,
  and resumes where this principal left it.

  The position is the one §13.3 names among this principal's own reports. §13.2 gives a
  category one unit, so a res whose position is measured in anything but milliseconds is
  a res with two units and not a place a queue can carry: it raises rather than starting
  silently at the beginning.
  """
  @spec play(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t(), Profile.t()) :: :ok
  def play(principal_id, device_id, work_id, %Profile{} = profile) do
    {entries, index} = queue_for(work_id, principal_id, profile)
    current = Enum.at(entries, index).res_id

    {:ok, _queue} =
      Consumption.save_play_queue(
        principal_id,
        entries,
        index,
        resumed(principal_id, current),
        device_id
      )

    Consumption.playing(principal_id, device_id, current)
  end

  @doc """
  Makes another entry of the queue current, at its own resume position.

  The queue itself is untouched: jumping to an entry is §12.3's own operation and does
  not reorder or shorten what a person assembled.
  """
  @spec jump(Ecto.UUID.t(), Ecto.UUID.t(), non_neg_integer()) ::
          :ok | {:error, :current_outside_queue | :no_queue}
  def jump(principal_id, device_id, index) do
    case Consumption.play_queue(principal_id) do
      nil ->
        {:error, :no_queue}

      queue ->
        entries = Enum.sort_by(queue.entries, & &1.position)

        with {:ok, entry} <- at_index(entries, index),
             {:ok, _queue} <- save(principal_id, device_id, entries, index, entry) do
          Consumption.playing(principal_id, device_id, entry.res_id)
        end
    end
  end

  defp at_index(entries, index) do
    case Enum.at(entries, index) do
      nil -> {:error, :current_outside_queue}
      entry -> {:ok, entry}
    end
  end

  defp save(principal_id, device_id, entries, index, entry) do
    Consumption.save_play_queue(
      principal_id,
      for(e <- entries, do: %{res_id: e.res_id, queued_from: e.queued_from}),
      index,
      resumed(principal_id, entry.res_id),
      device_id
    )
  end

  @doc """
  The entry after the one that is current, or nil where it is the last.

  §12.4's question: the offer at the end exists only where a next member does.
  """
  @spec next_after(current()) :: queued() | nil
  def next_after(%{queue: queue, index: index}), do: Enum.at(queue, index + 1)

  defp resumed(principal_id, res_id) do
    case Events.resume_position(principal_id, res_id) do
      nil ->
        0

      %{unit: :millisecond, position: position} ->
        position

      %{unit: unit} ->
        raise ArgumentError,
              "the position held for #{res_id} is measured in #{unit} and a queue's is in " <>
                "milliseconds, so this res is tracked in two units"
    end
  end

  @doc """
  The bytes playing one manifestation acts on.

  The manifestation rather than the work, because that is what a position is measured
  against and what a queue names.
  """
  @spec for_manifestation(Ecto.UUID.t()) :: {:ok, playable()} | {:error, refusal()}
  def for_manifestation(manifestation_id) do
    case carrier(manifestation_id) do
      nil -> as_a_region(manifestation_id)
      item_id -> whole(manifestation_id, item_id)
    end
  end

  @doc """
  The bytes playing a work acts on, under the requesting principal's own selection.

  §8.1's selection answers which expression a principal is given; which of that
  expression's manifestations is then taken by identifier, so a holding carrying several
  resolves to the same one across calls as §7.4 requires of what a surface shows.
  """
  @spec for_work(Ecto.UUID.t(), Ecto.UUID.t(), Profile.t()) ::
          {:ok, playable()} | {:error, refusal()}
  def for_work(work_id, principal_id, %Profile{} = profile) do
    selected = Selection.for_principal(work_id, principal_id, profile)

    case embodied_by(selected.expression.id) do
      nil -> {:error, {:holds_no_file, work_id}}
      manifestation_id -> for_manifestation(manifestation_id)
    end
  end

  defp whole(manifestation_id, item_id) do
    with {:ok, parts} <- parts(manifestation_id, item_id) do
      {:ok, %{parts: parts, from_ms: nil, to_ms: nil}}
    end
  end

  # Nothing holds a file for this manifestation, so either the household holds none or
  # its bytes are a region of another manifestation's.
  defp as_a_region(manifestation_id) do
    with %{target_id: target, start_ms: from, end_ms: to} <- extent_of(manifestation_id),
         item_id when is_binary(item_id) <- carrier(target),
         {:ok, parts} <- parts(manifestation_id, item_id) do
      {:ok, %{parts: parts, from_ms: from, to_ms: to}}
    else
      nil -> {:error, {:holds_no_file, manifestation_id}}
      {:error, refusal} -> {:error, refusal}
    end
  end

  # The address spec-04 §6.4 wrote: it is linked to the manifestation whose region it
  # describes, and its target is the manifestation carrying the bytes.
  defp extent_of(manifestation_id) do
    Repo.one(
      from a in Association,
        join: address in Address,
        on: address.id == a.subject_id,
        where: a.refinement == "extent-of",
        where: a.object_id == ^manifestation_id,
        select: %{
          target_id: address.target_id,
          start_ms: address.start_ms,
          end_ms: address.end_ms
        }
    )
  end

  defp embodied_by(expression_id) do
    Repo.one(
      from b in Embodiment,
        where: b.expression_id == ^expression_id,
        order_by: b.manifestation_id,
        limit: 1,
        select: b.manifestation_id
    )
  end

  defp carrier(manifestation_id) do
    Repo.one(
      from d in DigitalItem,
        where: d.manifestation_id == ^manifestation_id,
        order_by: d.id,
        limit: 1,
        select: d.id
    )
  end

  defp parts(res_id, item_id) do
    case masters(item_id) do
      [] -> {:error, {:not_normalized, res_id}}
      masters -> measured(res_id, masters, durations(item_id))
    end
  end

  # In part order, so a sequence plays in the order it was read. A holding in one file
  # records no sequence, which sorts ahead of any.
  defp masters(item_id) do
    Repo.all(
      from a in Asset,
        join: r in AssetRole,
        on: r.asset_id == a.id,
        where: a.digital_item_id == ^item_id,
        where: r.role_class == :normalized,
        where: a.id not in subquery(from b in RecycledRes, select: b.res_id),
        where: a.id not in subquery(from t in Tombstone, select: t.res_id),
        order_by: [asc_nulls_first: a.part_sequence, asc: a.id],
        select: %{id: a.id, format: a.format, part_sequence: a.part_sequence}
    )
  end

  # A part's length is its own probe's, which spec-04 §6.1 records against the asset
  # whose bytes it read. That is the acquired asset, so the two are paired by the part
  # they are of.
  defp durations(item_id) do
    acquired =
      Repo.all(
        from a in Asset,
          join: r in AssetRole,
          on: r.asset_id == a.id,
          where: a.digital_item_id == ^item_id,
          where: r.role_class == :acquired,
          select: {a.id, a.part_sequence}
      )

    bodies = acquired |> Enum.map(&elem(&1, 0)) |> Annotations.current_bodies("probe")

    Map.new(acquired, fn {asset_id, sequence} ->
      {sequence, bodies[asset_id] && Streams.duration_ms(bodies[asset_id])}
    end)
  end

  defp measured(_res_id, [only], durations) do
    {:ok, [part(only, durations[only.part_sequence])]}
  end

  defp measured(res_id, masters, durations) do
    parts = Enum.map(masters, &part(&1, durations[&1.part_sequence]))

    if Enum.any?(parts, &is_nil(&1.duration_ms)),
      do: {:error, {:sequence_unmeasured, res_id}},
      else: {:ok, parts}
  end

  defp part(master, duration_ms) do
    %{
      asset_id: master.id,
      media_type: Registry.media_type(master.format),
      duration_ms: duration_ms
    }
  end

  @doc """
  What a surface says where there is nothing to play.

  The words are here rather than in the component because the three are different facts
  and a surface wording them alike would report a holding the household never had as one
  whose bytes are still being worked on.
  """
  @spec why({atom(), Ecto.UUID.t()}) :: String.t()
  def why({:holds_no_file, _work_id}),
    do: "The household describes this and holds no file for it, so there is nothing to play."

  def why({:not_normalized, _work_id}),
    do: "The bytes of this have not been normalized yet, so there is nothing to play from."

  def why({:sequence_unmeasured, _work_id}),
    do:
      "This is held in several files and one of them has no measured length, " <>
        "so a position in it cannot be placed."
end
