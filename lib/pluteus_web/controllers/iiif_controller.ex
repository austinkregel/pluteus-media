defmodule PluteusWeb.IiifController do
  @moduledoc """
  A tiled image, under the [IIIF-IMAGE] URL grammar ([spec-10] §11.2).

  Adopting the grammar is what makes the client off-the-shelf: a deep-zoom viewer that
  already speaks it needs no knowledge of this deployment beyond the identifier. The
  grammar's own paths are the route, so `{region}/{size}/{rotation}/{quality}.{format}`
  is read from the path rather than from a query string.

  **The information document is the contract.** It names the identifier, the tile size,
  the scale factors and the compliance level, and a client asks for nothing the document
  did not offer. `vips` writes a level 0 pyramid — only the tiles it generated are
  addressable — and the deployment declares `regionByPct` and `sizeByW` as extra
  features rather than claiming level 1, because the rest of level 1 is not offered and
  claiming it would be a promise.

  The pyramid is a presentation asset like any other, so it is generated on demand,
  evicted under §11.6's bound, and its absence is not an error.
  """

  use PluteusWeb, :controller

  alias Pluteus.Catalog.Res
  alias Pluteus.Lifecycle
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Asset
  alias Pluteus.Presentation.Registry
  alias Pluteus.Presentation.Tiles
  alias Pluteus.Workers.GeneratePresentationAsset
  alias PluteusWeb.Native
  alias PluteusWeb.Problem

  def information(conn, %{"id" => id}) do
    with {:ok, subject_id} <- subject(conn, id),
         %Asset{} = pyramid <- held(subject_id) do
      {:ok, served} = Presentation.serve(pyramid)
      {:ok, document} = Tiles.information(served.location, identifier(conn, id))

      json(conn, document)
    else
      {:error, answer} -> answer.(conn)
      nil -> awaited(conn, id)
    end
  end

  def tile(conn, %{"id" => id, "region" => region, "size" => size} = params) do
    with {:ok, subject_id} <- subject(conn, id),
         %Asset{} = pyramid <- held(subject_id),
         {:ok, path} <- within(region, size, params) do
      {:ok, served} = Presentation.serve(pyramid)

      case Tiles.entry(served.location, path, identifier(conn, id)) do
        {:ok, bytes, media_type} ->
          conn
          |> put_resp_header("presentation-profile", profile())
          |> put_resp_content_type(media_type, nil)
          |> send_resp(200, bytes)

        {:error, :no_such_tile} ->
          # Level 0 offers exactly the tiles the pyramid holds. A request for another is
          # not a missing artefact; it is outside what the information document offered.
          Native.not_found(conn)
      end
    else
      {:error, answer} -> answer.(conn)
      nil -> awaited(conn, id)
      :error -> refused(conn)
    end
  end

  defp subject(conn, id) do
    kind = conn.assigns.kind

    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> live(uuid, kind)
      :error -> {:error, &Native.not_found(&1)}
    end
  end

  defp live(uuid, kind) do
    case Lifecycle.state(uuid) do
      {:live, %Res{kind: ^kind}} ->
        {:ok, uuid}

      {:recycled, %Res{kind: ^kind}, recycling} ->
        {:error, &gone(&1, "recycled", %{restorable_until: iso(recycling.purge_after)})}

      {:purged, %Res{kind: ^kind}, tombstone} ->
        {:error, &gone(&1, "purged", %{purged_at: iso(tombstone.purged_at)})}

      _absent ->
        {:error, &Native.not_found(&1)}
    end
  end

  defp held(subject_id), do: Presentation.get(subject_id, profile())

  # The absence of a pyramid is answered the way every other absence is (§11.6): queued
  # where there are bytes to build one from, and stated where there are not.
  defp awaited(conn, id) do
    {:ok, subject_id} = Ecto.UUID.cast(id)
    conn = put_resp_header(conn, "presentation-profile", profile())

    case Presentation.source_for(subject_id) do
      nil ->
        send_resp(conn, 204, "")

      _source ->
        {:ok, _job} = GeneratePresentationAsset.queue(subject_id, profile())
        send_resp(conn, 202, "")
    end
  end

  # The grammar's rotation and quality are fixed by what the pyramid holds, so a request
  # naming others is refused rather than answered with something else.
  defp within(region, size, params) do
    rotation = Map.get(params, "rotation", "0")
    quality = Map.get(params, "quality", "default.jpg")

    if rotation == "0" and quality == "default.jpg" do
      {:ok, Path.join([translated(region), size, rotation, quality])}
    else
      :error
    end
  end

  # A percentage region is the one form §11.2 requires be accepted, and the deep link's
  # spelling of it is translated rather than stored (spec-01 §8.4).
  defp translated("percent:" <> _rest = region), do: Tiles.pct(region)
  defp translated(region), do: region

  # The image service's own base URL, which a client resolves every tile against. It is
  # built from the kind and the identifier rather than read off the request, so that
  # `info.json` and a tile answer with the same one.
  defp identifier(conn, id) do
    path = Map.fetch!(Native.paths(), conn.assigns.kind)

    Path.join([PluteusWeb.Endpoint.url(), path, id, "iiif"])
  end

  defp profile, do: Map.fetch!(Registry.tiling(), "name")

  defp refused(conn) do
    Problem.send(conn, 400, %{
      type: Problem.type("tile-refused"),
      title: "tile refused",
      detail:
        "this pyramid offers rotation 0 and quality default.jpg, as its information " <>
          "document states"
    })
  end

  defp gone(conn, type, fields) do
    Problem.send(conn, 410, Map.merge(%{type: Problem.type(type), title: type}, fields))
  end

  defp iso(at), do: DateTime.to_iso8601(at)
end
