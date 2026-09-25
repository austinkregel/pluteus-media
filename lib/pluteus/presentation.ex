defmodule Pluteus.Presentation do
  @moduledoc """
  The derived artefacts surfaces display ([spec-10] §11).

  A surface asks for one by subject and profile name. What comes back is a row or
  nothing, and nothing is not an error (§11.6): the caller decides whether to queue
  generation, and either absence — with a source to generate from, or without one —
  is answered on the wire as a 2xx.

  **Bytes live under a `presentation/` prefix.** `Pluteus.Ingest.find_stray_bytes/1`
  walks exactly `XX/YY/<uuid>` and reports anything it finds there that no holding
  accounts for; a presentation location is one segment deeper and matches neither
  its glob nor its layout, so a cache fill is never reported as unaccounted bytes.

  Nothing here is backed up (spec-01 §13.7). Everything here is regenerable from the
  asset it names, which is what makes eviction safe.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Catalog.AssetRole
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Lifecycle.RecycledRes
  alias Pluteus.Lifecycle.Tombstone
  alias Pluteus.Presentation.Asset
  alias Pluteus.Presentation.Registry
  alias Pluteus.Presentation.Waveform
  alias Pluteus.Repo
  alias Pluteus.Storage

  @doc """
  The artefact for one subject and profile, or nil.

  Reading does not mark it served: `serve/1` does, so that a lookup made to decide
  whether to generate does not reorder the eviction queue.
  """
  @spec get(Ecto.UUID.t(), String.t(), non_neg_integer()) :: Asset.t() | nil
  def get(subject_id, profile, ordinal \\ 0) do
    Repo.get_by(Asset, subject_id: subject_id, profile: profile, ordinal: ordinal)
  end

  @doc """
  Every artefact of one profile across many subjects, keyed by subject.

  A page of tiles needs one query for its images, not one per tile.
  """
  @spec for_subjects([Ecto.UUID.t()], String.t()) :: %{Ecto.UUID.t() => Asset.t()}
  def for_subjects([], _profile), do: %{}

  def for_subjects(subject_ids, profile) do
    Map.new(
      Repo.all(
        from p in Asset,
          where: p.subject_id in ^subject_ids and p.profile == ^profile and p.ordinal == 0,
          select: {p.subject_id, p}
      )
    )
  end

  @doc """
  Every artefact held for a subject, whatever its profile.
  """
  @spec for_subject(Ecto.UUID.t()) :: [Asset.t()]
  def for_subject(subject_id) do
    Repo.all(
      from p in Asset, where: p.subject_id == ^subject_id, order_by: [p.profile, p.ordinal]
    )
  end

  @doc """
  Records an artefact whose bytes are already stored.

  Writing the row after the bytes is what keeps the invariant the schema rests on:
  a row exists only where the bytes do. A regeneration replaces the row for the same
  subject, profile and ordinal, because the location derives from those three and the
  new bytes are already at it.
  """
  @spec record(map()) :: {:ok, Asset.t()} | {:error, Ecto.Changeset.t()}
  def record(attrs) do
    %Asset{}
    |> Asset.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :location,
           :media_type,
           :size,
           :digest,
           :digest_algorithm,
           :width,
           :height,
           :descriptor,
           :source_asset_id,
           :source_digest,
           :generated_at,
           :last_served_at,
           :updated_at
         ]},
      conflict_target: [:subject_id, :profile, :ordinal]
    )
  end

  @doc """
  Marks an artefact as served now, which is the order §11.6 evicts in.
  """
  @spec serve(Asset.t(), DateTime.t()) :: {:ok, Asset.t()} | {:error, Ecto.Changeset.t()}
  def serve(%Asset{} = asset, now \\ DateTime.utc_now()) do
    asset
    |> Ecto.Changeset.change(last_served_at: now)
    |> Repo.update()
  end

  @doc """
  Removes an artefact's row and its bytes.

  The row goes first. A row with no bytes would be served as present and answer an
  empty body; bytes with no row are reclaimed by the next eviction pass, so the
  order that survives a crash halfway is this one.
  """
  @spec discard(Asset.t()) :: :ok
  def discard(%Asset{} = asset) do
    {1, _} =
      Repo.delete_all(
        from p in Asset,
          where:
            p.subject_id == ^asset.subject_id and p.profile == ^asset.profile and
              p.ordinal == ^asset.ordinal
      )

    Storage.delete(asset.location)

    :ok
  end

  @doc """
  Removes every artefact of the given res, and their bytes.

  Purging a res takes its derivatives with it (spec-01 §13.7): they are regenerable
  from bytes that are themselves going.
  """
  @spec discard_for([Ecto.UUID.t()]) :: non_neg_integer()
  def discard_for([]), do: 0

  def discard_for(res_ids) do
    held =
      Repo.all(
        from p in Asset,
          where: p.subject_id in ^res_ids or p.source_asset_id in ^res_ids,
          select: {p.subject_id, p.profile, p.ordinal, p.location}
      )

    for {_subject, _profile, _ordinal, location} <- held, do: Storage.delete(location)

    {removed, _} =
      Repo.delete_all(
        from p in Asset, where: p.subject_id in ^res_ids or p.source_asset_id in ^res_ids
      )

    removed
  end

  @doc """
  Where an artefact's bytes lie.

  Derived from the three columns that identify it, so regenerating one writes over
  what it replaces rather than accumulating. The first two segments shard on the
  subject the way `Pluteus.Ingest.location_for/1` shards on an identifier, and the
  `presentation/` head is what keeps the path out of the holdings layout.
  """
  @spec location_for(Ecto.UUID.t(), String.t(), non_neg_integer(), String.t()) :: String.t()
  def location_for(subject_id, profile, ordinal, extension) do
    hex = String.replace(subject_id, "-", "")

    Path.join([
      "presentation",
      String.slice(hex, -2, 2),
      String.slice(hex, -4, 2),
      "#{subject_id}-#{profile}-#{ordinal}.#{extension}"
    ])
  end

  @doc """
  Whether an artefact still describes the bytes it was made from.

  A source whose digest has moved has been re-encoded or replaced, and an artefact
  drawn from what it used to be is stale. Normalization replacing a master is the
  ordinary way this happens.
  """
  @spec current?(Asset.t(), String.t()) :: boolean()
  def current?(%Asset{source_digest: source_digest}, digest_now),
    do: source_digest == digest_now

  @doc """
  The profile to serve a waveform at, for a surface that wants this many points per
  second (§11.4, criterion 30).

  The coarsest profile that supports the zoom, because a coarser one would have to be
  stretched. Nil where no profile reaches it: a surface asking for finer than anything
  measured is told so rather than handed an artefact to interpolate, since decimating
  a stored waveform is a coarser view of the same shape and interpolating one draws a
  shape the audio does not have.

  Where two profiles reach the zoom equally — which happens for a short recording,
  whose fixed-count overview is as dense as a rate-based detail — the one §20 generates
  at ingest wins, because it is already there and the other would be encoded to say the
  same thing.
  """
  @spec waveform_for_zoom(number(), non_neg_integer()) :: map() | nil
  def waveform_for_zoom(points_per_second, duration_ms) do
    at_ingest = Registry.generated_at_ingest()

    [Registry.waveform_overview() | Registry.waveform_detail()]
    |> Enum.filter(&Waveform.supports_zoom?(resolution_of(&1, duration_ms), points_per_second))
    |> Enum.min_by(
      fn profile ->
        {Waveform.resolution(resolution_of(profile, duration_ms)),
         if(Map.fetch!(profile, "name") in at_ingest, do: 0, else: 1)}
      end,
      fn -> nil end
    )
  end

  defp resolution_of(profile, duration_ms), do: Map.put(profile, "duration_ms", duration_ms)

  @doc """
  Whether an artefact a surface holds can be drawn at this zoom without inventing
  anything (criterion 30).
  """
  @spec supports_zoom?(Asset.t(), number()) :: boolean()
  def supports_zoom?(%Asset{descriptor: descriptor}, points_per_second),
    do: Waveform.supports_zoom?(descriptor, points_per_second)

  @doc """
  The profile an OpenSubsonic `size` maps to (spec-07 §6.7, §11.1).
  """
  @spec profile_for_size(pos_integer() | nil) :: map()
  def profile_for_size(size), do: Registry.image_profile_for_size(size)

  @doc """
  What the bytes behind a res turned out to be: the broad class spec-04 §5.3 recorded,
  and for a companion the kind §4.6 recognized it as. Nil where no bytes were placed.

  The kind refines the class because a companion's category *is* its kind (§6.3), and
  a cover and a lyrics file are as unalike as an image and a document. Without it,
  either every companion could have an image profile or none could.
  """
  @spec classification(Ecto.UUID.t()) :: {atom(), String.t() | nil} | nil
  def classification(res_id) do
    Repo.one(
      from a in Acquisition,
        where: a.digital_item_id == subquery(digital_item_of(res_id)),
        order_by: [asc: a.id],
        limit: 1,
        select: {a.media_class, a.companion_kind}
    )
  end

  # A manifestation, a digital item or an asset all name one holding, and everything
  # here hangs off its digital item. Resolving that first is what lets an asset be a
  # subject even where the asset asked about is not the one a derivative is drawn
  # from: a cover whose original was re-encoded is still the same holding.
  defp digital_item_of(res_id) do
    from d in DigitalItem,
      left_join: a in Pluteus.Catalog.Asset,
      on: a.digital_item_id == d.id,
      where: d.manifestation_id == ^res_id or d.id == ^res_id or a.id == ^res_id,
      order_by: [asc: d.id],
      limit: 1,
      select: d.id
  end

  @doc """
  The asset a derivative of this res would be generated from, or nil.

  The Normalized master, because a derivative should be drawn from the copy the
  deployment intends to keep reading. Its absence is what distinguishes an artefact
  waiting to be generated from one there is nothing to generate: a manifestation the
  household describes but holds no file for has neither (spec-01 §5.2).
  """
  @spec source_for(Ecto.UUID.t()) :: Pluteus.Catalog.Asset.t() | nil
  def source_for(res_id) do
    Repo.one(
      from a in Pluteus.Catalog.Asset,
        join: r in AssetRole,
        on: r.asset_id == a.id and r.role_class == :normalized,
        where: a.digital_item_id == subquery(digital_item_of(res_id)),
        where: a.id not in subquery(from(b in RecycledRes, select: b.res_id)),
        where: a.id not in subquery(from(t in Tombstone, select: t.res_id)),
        order_by: [asc: a.id],
        limit: 1
    )
  end

  @doc """
  Whether a profile is one this subject can have at all (§11.1).

  §11 groups its artefacts by the kind of thing they are made from, and each profile
  names the broad classes it applies to. A waveform of a photograph is not an
  artefact that has not been generated yet; it is not an artefact.

  A subject whose class is unknown — nothing has been placed under it — applies to
  nothing, because there are no bytes to derive from.
  """
  @spec applies?(map(), Ecto.UUID.t()) :: boolean()
  def applies?(profile, subject_id) do
    case classification(subject_id) do
      nil -> false
      {:companion, kind} -> kind in Map.fetch!(profile, "companion_kinds")
      {class, _no_kind} -> Atom.to_string(class) in Map.fetch!(profile, "classes")
    end
  end
end
