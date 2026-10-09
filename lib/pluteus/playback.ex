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
  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.AssetRole
  alias Pluteus.Catalog.Association
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Grouping
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Selection
  alias Pluteus.Consumption
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
  @spec queue_for(Ecto.UUID.t()) :: {[Consumption.entry()], non_neg_integer()}
  def queue_for(work_id) do
    case Grouping.members_of(work_id) do
      [] -> from_its_grouping(work_id)
      members -> {entries(members, work_id), 0}
    end
  end

  defp from_its_grouping(work_id) do
    case Grouping.grouping_of(work_id) do
      nil ->
        {[%{res_id: work_id, queued_from: nil}], 0}

      grouping ->
        members = Grouping.members_of(grouping)

        {entries(members, grouping), at(members, work_id, grouping)}
    end
  end

  # A grouping that does not carry the member it was reached through is a broken
  # relation, not a queue to start at the beginning of.
  defp at(members, work_id, grouping) do
    Enum.find_index(members, &(&1 == work_id)) ||
      raise ArgumentError,
            "#{work_id} is a member of #{grouping}, which does not carry it among its members"
  end

  defp entries(members, queued_from) do
    for res_id <- members, do: %{res_id: res_id, queued_from: queued_from}
  end

  @doc """
  The bytes playing a work acts on, under the requesting principal's own selection.
  """
  @spec for_work(Ecto.UUID.t(), Ecto.UUID.t(), Profile.t()) ::
          {:ok, playable()} | {:error, refusal()}
  def for_work(work_id, principal_id, %Profile{} = profile) do
    selected = Selection.for_principal(work_id, principal_id, profile)

    case selected.digital_item do
      nil -> as_a_region(work_id, selected.expression.id)
      item -> whole(work_id, item)
    end
  end

  defp whole(work_id, item_id) do
    with {:ok, parts} <- parts(work_id, item_id) do
      {:ok, %{parts: parts, from_ms: nil, to_ms: nil}}
    end
  end

  # The expression embodies a manifestation nothing holds a file for, so either the
  # household holds no file for it or its bytes are a region of something else's.
  defp as_a_region(work_id, expression_id) do
    with %{target_id: target, start_ms: from, end_ms: to} <- extent_of(expression_id),
         item_id when is_binary(item_id) <- carrier(target),
         {:ok, parts} <- parts(work_id, item_id) do
      {:ok, %{parts: parts, from_ms: from, to_ms: to}}
    else
      nil -> {:error, {:holds_no_file, work_id}}
      {:error, refusal} -> {:error, refusal}
    end
  end

  # The address spec-04 §6.4 wrote: its target is the manifestation carrying the bytes
  # and its bounds are the region of them this work is.
  defp extent_of(expression_id) do
    Repo.one(
      from a in Association,
        join: address in Address,
        on: address.id == a.subject_id,
        join: b in Embodiment,
        on: b.manifestation_id == a.object_id,
        where: b.expression_id == ^expression_id,
        where: a.refinement == "extent-of",
        select: %{
          target_id: address.target_id,
          start_ms: address.start_ms,
          end_ms: address.end_ms
        }
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

  defp parts(work_id, item_id) do
    case masters(item_id) do
      [] -> {:error, {:not_normalized, work_id}}
      masters -> measured(work_id, masters, durations(item_id))
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

  defp measured(_work_id, [only], durations) do
    {:ok, [part(only, durations[only.part_sequence])]}
  end

  defp measured(work_id, masters, durations) do
    parts = Enum.map(masters, &part(&1, durations[&1.part_sequence]))

    if Enum.any?(parts, &is_nil(&1.duration_ms)),
      do: {:error, {:sequence_unmeasured, work_id}},
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
