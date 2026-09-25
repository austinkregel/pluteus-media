defmodule PluteusWeb.ContentController do
  @moduledoc """
  An asset's bytes, as stored (spec-07 §4.4).

  Ranges are `PluteusWeb.StoredBytes`'. Nothing is transformed: a transcode is
  spec-08's.
  """

  use PluteusWeb, :controller

  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.Res
  alias Pluteus.Ingest.Registry
  alias Pluteus.Lifecycle
  alias Pluteus.Repo
  alias PluteusWeb.Native
  alias PluteusWeb.Problem
  alias PluteusWeb.StoredBytes

  def show(conn, %{"id" => id}) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:live, %Res{kind: :asset}} <- Lifecycle.state(uuid) do
      serve(conn, Repo.get!(Asset, uuid))
    else
      {:recycled, %Res{kind: :asset}, recycling} ->
        gone(conn, "recycled", %{restorable_until: DateTime.to_iso8601(recycling.purge_after)})

      {:purged, %Res{kind: :asset}, tombstone} ->
        gone(conn, "purged", %{purged_at: DateTime.to_iso8601(tombstone.purged_at)})

      _absent ->
        Native.not_found(conn)
    end
  end

  @doc false
  def serve(conn, %Asset{} = asset) do
    StoredBytes.send_stored(conn, asset.location,
      content_type: Registry.media_type(asset.format),
      etag: asset.digest
    )
  end

  defp gone(conn, type, fields) do
    Problem.send(conn, 410, Map.merge(%{type: Problem.type(type), title: type}, fields))
  end
end
