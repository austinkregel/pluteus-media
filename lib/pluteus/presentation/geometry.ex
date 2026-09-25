defmodule Pluteus.Presentation.Geometry do
  @moduledoc """
  What a surface reserves space with, before it fetches an image ([spec-10] §11.2).

  **Geometry before bytes.** A collection whose tiles size themselves as images
  arrive reflows under the reader's hands, so a surface needs a visual res's
  dimensions in the same call that resolves its name — not a request per tile.

  The dimensions are the probe's. spec-04 §6.1 records the probe against the asset
  whose bytes it read, so a manifestation's geometry is the geometry of the asset
  carrying its bytes, and this gathers the two hops for a whole page at once.

  Where no probe has run the geometry is *not yet examined* (§5.2) and the ratio to
  reserve is the one §20 names for the category. That is why `reserve/2` answers a
  ratio whether or not the pixels are known: without one a tile collapses to zero
  height and the page jumps when the first image lands.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Annotations
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.AssetRole
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Ingest.Streams
  alias Pluteus.Lifecycle.RecycledRes
  alias Pluteus.Lifecycle.Tombstone
  alias Pluteus.Presentation.Registry
  alias Pluteus.Repo

  @typedoc """
  The pixels a res is drawn at, and the ratio that follows from them.
  """
  @type t :: %{
          required(:width) => pos_integer(),
          required(:height) => pos_integer(),
          required(:aspect_ratio) => float()
        }

  @doc """
  The geometry of each of many res, keyed by identifier. A res whose bytes nobody
  has probed is absent.

  Three queries whatever the number of res: the digital items carrying them, the
  assets realizing those, and the probe bodies of those assets.
  """
  @spec for_res([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => t()}
  def for_res([]), do: %{}

  def for_res(res_ids) do
    bearers = bearing_assets(res_ids)

    probes =
      bearers
      |> Map.values()
      |> Enum.uniq()
      |> Annotations.current_bodies("probe")

    for {res_id, asset_id} <- bearers,
        dimensions = Streams.dimensions(probes[asset_id]),
        dimensions != nil,
        into: %{} do
      {width, height} = dimensions
      {res_id, %{width: width, height: height, aspect_ratio: ratio(width, height)}}
    end
  end

  @doc """
  The aspect ratio a surface reserves for a res of this category.

  The measured ratio where the bytes have been probed, and §20's assumed ratio for
  the category otherwise. A category §20 gives no ratio — a companion kind, which is
  never presented as a holding (§12.2) — reserves nothing, because nothing draws it.
  """
  @spec reserve(t() | nil, String.t() | nil) :: float() | nil
  def reserve(%{aspect_ratio: aspect_ratio}, _category), do: aspect_ratio
  def reserve(nil, nil), do: nil
  def reserve(nil, category), do: Registry.assumed_aspect_ratio(category)

  # The asset whose bytes each res is drawn from: the Acquired asset of a digital
  # item carrying it. Acquired rather than Normalized, because the dimensions of
  # what arrived are the holding's own, and a re-encode that changed them would be
  # reporting the copy's shape as the thing's.
  defp bearing_assets(res_ids) do
    Map.new(
      Repo.all(
        from d in DigitalItem,
          join: a in Asset,
          on: a.digital_item_id == d.id,
          join: r in AssetRole,
          on: r.asset_id == a.id and r.role_class == :acquired,
          where: d.manifestation_id in ^res_ids or d.id in ^res_ids or a.id in ^res_ids,
          where: a.id not in subquery(from(b in RecycledRes, select: b.res_id)),
          where: a.id not in subquery(from(t in Tombstone, select: t.res_id)),
          order_by: [asc: a.id],
          select: {d.manifestation_id, d.id, a.id}
      )
      |> Enum.flat_map(fn {manifestation_id, item_id, asset_id} ->
        for res_id <- [manifestation_id, item_id, asset_id], res_id in res_ids do
          {res_id, asset_id}
        end
      end)
    )
  end

  defp ratio(width, height), do: Float.round(width / height, 4)
end
