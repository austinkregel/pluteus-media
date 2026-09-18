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
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.AssetRole
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Ingest.Finding
  alias Pluteus.Ingest.Registry
  alias Pluteus.Lifecycle
  alias Pluteus.Lifecycle.RecycledRes
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
    blocked =
      from f in Finding,
        where: f.stage == :normalize and is_nil(f.cleared_at),
        select: f.digital_item_id

    from(a in Acquisition,
      where: a.state == :placed,
      where: a.digital_item_id not in subquery(blocked),
      order_by: a.id
    )
    |> Repo.all()
    |> Enum.filter(&live?(&1.id))
    |> Enum.map(&{&1, standard_format.(&1.media_class)})
    |> Enum.filter(fn {acquisition, standard} -> due?(acquisition, standard) end)
    |> Enum.map(fn {acquisition, standard} ->
      {acquisition.digital_item_id, normalize(acquisition, standard)}
    end)
  end

  @doc """
  The live asset of a digital item holding the Normalized role, or nil.
  """
  @spec master_of(Ecto.UUID.t()) :: Asset.t() | nil
  def master_of(digital_item_id) do
    Repo.one(
      from a in Asset,
        join: r in AssetRole,
        on: r.asset_id == a.id and r.role_class == :normalized,
        where: a.digital_item_id == ^digital_item_id,
        where: a.id not in subquery(from b in RecycledRes, select: b.res_id),
        distinct: true
    )
  end

  defp due?(acquisition, standard) do
    original = Repo.get!(Asset, acquisition.id)

    case master_of(acquisition.digital_item_id) do
      nil ->
        true

      master ->
        original.essence == :lossless and standard != nil and master.format != standard["format"]
    end
  end

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
    previous = master_of(acquisition.digital_item_id)

    if re_encodes?(original, standard),
      do: re_encode(acquisition, original, previous, standard),
      else: adopt(original, previous)
  end

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
         :ok <- same_content(original.location, location, acquisition.media_class) do
      Actor.as(Principals.system!().id, fn ->
        {:ok, _} =
          Assets.normalize(
            original.id,
            %{
              id: id,
              location: location,
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

  defp encode(source, location, standard) do
    target = Storage.path(location)
    File.mkdir_p!(Path.dirname(target))

    args =
      ["-loglevel", "error", "-nostdin", "-i", Storage.path(source)] ++
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

  defp live?(asset_id), do: match?({:live, _}, Lifecycle.state(asset_id))
end
