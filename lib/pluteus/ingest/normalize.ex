defmodule Pluteus.Ingest.Normalize do
  @moduledoc """
  Gives each placed holding its standardized master (spec-04 §7, spec-03 §4).

  An acquired asset is adopted as its own master, and nothing is re-encoded,
  where its essence is lossy, unknown or not applicable, where the registry
  names no standard format for its broad class, or where it is already in that
  format. Otherwise its content is re-encoded into the standard format, and the
  result is accepted only where its decoded content hashes the same as the
  original's: a normalization that lost anything is a finding, never a master.

  When the standard format for a class changes, lossless holdings whose master
  is in another format are due again. The new master takes the Normalized role;
  a previous master that is only a copy is recycled, and one that is the
  acquired original gives up the role and keeps the Acquired one.

  Every catalog write is the deployment's own, attributed to the System
  principal.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Actor
  alias Pluteus.Assets
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.AssetRole
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Ingest.Finding
  alias Pluteus.Ingest.Registry
  alias Pluteus.Lifecycle
  alias Pluteus.Lifecycle.RecycledRes
  alias Pluteus.Lifecycle.Tombstone
  alias Pluteus.PlatformEvents
  alias Pluteus.Principals
  alias Pluteus.Repo
  alias Pluteus.Storage

  @doc """
  One pass of the normalize stage over every placed holding that is due and
  has no uncleared finding at this stage.

  `standard_format` gives the standard format for a broad class, or nil; it is
  the registry's unless a caller supplies another.
  """
  @spec normalize_due((atom() -> map() | nil)) :: [{Ecto.UUID.t(), atom()}]
  def normalize_due(standard_format \\ &Registry.standard_format/1) do
    # A finding that names no digital item blocks nothing, because it is not about one:
    # a derivative that could not be made is recorded against the subject it was for.
    # The guard is load-bearing rather than tidy — one NULL inside `NOT IN` makes the
    # predicate NULL for every row, so a single such finding would stop this stage for
    # the whole household and report nothing at all.
    blocked =
      from f in Finding,
        where: f.stage == :normalize and is_nil(f.cleared_at),
        where: not is_nil(f.digital_item_id),
        select: f.digital_item_id

    blocked
    |> considered()
    |> Repo.all()
    |> Enum.map(fn held -> {held, standard_format.(held.acquisition.media_class)} end)
    |> Enum.filter(fn {held, standard} -> due?(held, standard) end)
    |> Enum.map(fn {%{acquisition: acquisition}, standard} ->
      {acquisition.digital_item_id,
       Ingest.isolated(:normalize, %{digital_item_id: acquisition.digital_item_id}, fn ->
         normalize(acquisition, standard)
       end)}
    end)
  end

  # Every placed holding this pass could have something to do about, with the two facts
  # that decide whether it does: its own essence, and the format of the master already
  # standing for its part.
  #
  # Both are asked of the selection rather than of each holding in turn. A pass that asks
  # per holding costs queries in proportion to what the household has already finished
  # normalizing, which is everything — so the stage spent most of a minute, every minute,
  # establishing that there was nothing to do.
  #
  # Whether the format is the standard one stays outside the query, because the standard
  # is the registry's answer for a broad class and not a column. What this narrows to is
  # the holdings whose answer could differ.
  defp considered(blocked) do
    from a in Acquisition,
      left_join: original in Asset,
      on: original.id == a.id,
      left_join: master in subquery(masters()),
      on:
        master.digital_item_id == a.digital_item_id and
          fragment("? IS NOT DISTINCT FROM ?", master.part_sequence, original.part_sequence),
      where: a.state == :placed,
      where: a.digital_item_id not in subquery(blocked),
      # Live, which for an asset is the three things `Pluteus.Lifecycle.state/1` reads: a
      # res that is there, carrying no tombstone and in nobody's recycling. An asset row
      # references its res, so holding one is the first of the three.
      where: a.id not in subquery(from(b in RecycledRes, select: b.res_id)),
      where: a.id not in subquery(from(t in Tombstone, select: t.res_id)),
      order_by: a.id,
      select: %{
        acquisition: a,
        asset_id: original.id,
        essence: original.essence,
        master_format: master.format
      }
  end

  # The live asset holding the Normalized role, per holding and per part. The same set
  # `master_of/2` answers from, taken for the selection at once.
  defp masters do
    from asset in Asset,
      join: role in AssetRole,
      on: role.asset_id == asset.id and role.role_class == :normalized,
      where: asset.id not in subquery(from(b in RecycledRes, select: b.res_id)),
      distinct: true,
      select: %{
        digital_item_id: asset.digital_item_id,
        part_sequence: asset.part_sequence,
        format: asset.format
      }
  end

  @doc """
  The live asset holding the Normalized role for a holding carried by one file, or nil.

  A holding in several files has a master per part, so there is no one answer and this
  raises rather than returning whichever row came back first. `master_of/2` is what names
  the part.
  """
  @spec master_of(Ecto.UUID.t()) :: Asset.t() | nil
  def master_of(digital_item_id) do
    case Repo.all(parts_of(digital_item_id)) do
      [] ->
        nil

      [only] ->
        only

      masters ->
        raise ArgumentError,
              "digital item #{digital_item_id} is carried by #{length(masters)} files, " <>
                "each with its own master, so which is meant has to be named"
    end
  end

  @doc """
  The live asset holding the Normalized role for one part of a holding, or nil.

  The part is what the role is per: `one_normalized_master` counts within
  `(digital item, part sequence)`, and a reading in several parts has a master for each.
  A holding carried by one file records no sequence, which `nil` names.
  """
  @spec master_of(Ecto.UUID.t(), integer() | nil) :: Asset.t() | nil
  def master_of(digital_item_id, part_sequence) do
    Repo.one(
      from a in parts_of(digital_item_id),
        where: fragment("? IS NOT DISTINCT FROM ?", a.part_sequence, ^part_sequence)
    )
  end

  defp parts_of(digital_item_id) do
    from a in Asset,
      join: r in AssetRole,
      on: r.asset_id == a.id and r.role_class == :normalized,
      where: a.digital_item_id == ^digital_item_id,
      where: a.id not in subquery(from b in RecycledRes, select: b.res_id),
      distinct: true
  end

  # A placed holding whose asset is gone is a broken invariant rather than a holding with
  # nothing to do, so it raises here as reading the asset by identifier always did.
  defp due?(%{asset_id: nil, acquisition: acquisition}, _standard) do
    raise "the placed acquisition #{acquisition.id} holds no asset"
  end

  # Due is asked of a part and not of a holding. Asked of the holding, the second file of
  # a reading in several parts is judged against the first file's master, found to need no
  # standard format it does not already have, and left with no master of its own — so
  # nothing can be played or served from it.
  defp due?(%{master_format: nil}, _standard), do: true
  defp due?(_held, nil), do: false

  defp due?(%{essence: :lossless, master_format: format}, standard),
    do: format != standard["format"]

  defp due?(_held, _standard), do: false

  defp re_encodes?(%Asset{essence: :lossless, format: format}, %{"format" => standard}),
    do: format != standard

  defp re_encodes?(_original, _standard), do: false

  @doc """
  Normalizes one placed holding against a standard format, or nil where its
  class has none.
  """
  @spec normalize(Acquisition.t(), map() | nil) :: :adopted | :re_encoded | :finding
  def normalize(%Acquisition{} = acquisition, standard) do
    original = Repo.get!(Asset, acquisition.id)

    # The master this one replaces is the one for the same part. Taken for the holding,
    # adopting the second file of a reading would recycle the first file's master.
    previous = master_of(acquisition.digital_item_id, original.part_sequence)

    outcome =
      if re_encodes?(original, standard),
        do: re_encode(acquisition, original, previous, standard),
        else: adopt(original, previous)

    announce(outcome, acquisition.digital_item_id)
  end

  # spec-01 §11.2's platform class: the household sees its holdings gain a master,
  # and this is the deployment's own work, so the System principal records it (§3).
  # A failure is not one of these — it reaches a person as a finding (§9), which has
  # a surface of its own. Two clauses and no catch-all, so an outcome added to
  # `normalize/2` raises rather than going unannounced.
  defp announce(outcome, digital_item_id) when outcome in [:adopted, :re_encoded] do
    {:ok, _event} =
      PlatformEvents.record("normalized", {:res, digital_item_id}, Principals.system!().id)

    outcome
  end

  defp announce(:finding, _digital_item_id), do: :finding

  defp adopt(original, previous) do
    Actor.as(Principals.system!().id, fn ->
      unless previous && previous.id == original.id do
        {:ok, _} = Assets.adopt_as_normalized(original.id, "standardized-master")
        retire(previous)
      end

      :adopted
    end)
  end

  defp re_encode(acquisition, original, previous, standard) do
    id = UUIDv7.generate()
    location = Ingest.location_for(id)

    with :ok <- encode(original.location, location, standard),
         :ok <- same_content(original.location, location, acquisition.media_class),
         {:ok, measurement} <- measure(location) do
      Actor.as(Principals.system!().id, fn ->
        {:ok, _} =
          Assets.normalize(
            original.id,
            %{
              id: id,
              location: location,
              measurement: measurement,
              verification_interval_seconds: original.verification_interval_seconds,
              role: "standardized-master"
            },
            %{
              nomen_string:
                Path.rootname(Path.basename(acquisition.inbox_path)) <>
                  "." <> standard["extension"],
              provenance: :automatic
            }
          )

        retire(previous)
        :re_encoded
      end)
    else
      {:error, kind, detail} ->
        _ = Storage.delete(location)

        Ingest.record_finding(%{
          stage: :normalize,
          kind: kind,
          permanent: true,
          detail: Map.put(detail, :removed, location),
          digital_item_id: acquisition.digital_item_id
        })

        :finding
    end
  end

  # A master that is also the acquired original keeps its bytes and its
  # Acquired role; one that is only a copy is regenerable, and goes to the bin.
  defp retire(nil), do: :ok

  defp retire(%Asset{id: id}) do
    if :acquired in Assets.role_classes_of(id) do
      Repo.delete_all(
        from r in AssetRole, where: r.asset_id == ^id and r.role_class == :normalized
      )

      :ok
    else
      {:ok, _} = Lifecycle.recycle(id, Principals.system!().id)
      :ok
    end
  end

  # The master is read before the transaction that records it opens.
  defp measure(location) do
    case Catalog.measure(location) do
      {:ok, measurement} -> {:ok, measurement}
      {:error, reason} -> {:error, "master_unreadable", %{reason: inspect(reason)}}
    end
  end

  defp encode(source, location, standard) do
    target = Storage.path(location)
    File.mkdir_p!(Path.dirname(target))

    # Two threads: the ingest queue already says how many holdings normalize at once, and
    # ffmpeg's default of one thread per core multiplied by that leaves nothing for the
    # deployment to answer on.
    args =
      ["-loglevel", "error", "-nostdin", "-threads", "2", "-i", Storage.path(source)] ++
        ["-map", "0", "-c", "copy", "-c:a", standard["codec"], "-f", standard["muxer"], target]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, "encoding_failed", %{status: status, output: output}}
    end
  end

  # The re-encoded content, decoded, must be the original's, decoded. A hash
  # of the decoded samples tells a lossless re-encode from one that rounded,
  # resampled or dropped anything.
  defp same_content(source, location, media_class) do
    streams = if media_class == :video, do: "0:v", else: "0:a"

    case {decoded_hash(source, streams), decoded_hash(location, streams)} do
      {same, same} ->
        :ok

      {original, copy} ->
        {:error, "normalization_lost_fidelity", %{original: original, copy: copy}}
    end
  end

  defp decoded_hash(location, streams) do
    args = [
      "-loglevel",
      "error",
      "-nostdin",
      "-threads",
      "2",
      "-i",
      Storage.path(location),
      "-map",
      streams,
      "-f",
      "md5",
      "-"
    ]

    {output, 0} = System.cmd("ffmpeg", args)
    String.trim(output)
  end
end
