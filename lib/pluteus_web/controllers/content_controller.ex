defmodule PluteusWeb.ContentController do
  @moduledoc """
  An asset's bytes, as stored (spec-07 §4.4).

  A single byte range is honoured with `206 Partial Content`, as a player
  seeking asks for it; a range beyond the end is `416`. A request naming more
  than one range is served whole, which HTTP permits and which no player seeking
  needs otherwise. Nothing is transformed: a transcode is spec-08's.
  """

  use PluteusWeb, :controller

  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.Res
  alias Pluteus.Ingest.Registry
  alias Pluteus.Lifecycle
  alias Pluteus.Repo
  alias Pluteus.Storage
  alias PluteusWeb.Native
  alias PluteusWeb.Problem

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
    path = Storage.path(asset.location)
    size = File.stat!(path).size

    conn =
      conn
      |> put_resp_content_type(Registry.media_type(asset.format), nil)
      |> put_resp_header("accept-ranges", "bytes")
      |> put_resp_header("etag", ~s("#{asset.digest}"))

    case range(get_req_header(conn, "range"), size) do
      :whole ->
        send_file(conn, 200, path)

      {:ok, first, last} ->
        conn
        |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
        |> send_file(206, path, first, last - first + 1)

      :unsatisfiable ->
        conn
        |> put_resp_header("content-range", "bytes */#{size}")
        |> send_resp(416, "")
    end
  end

  defp range([header], size) do
    case Regex.run(~r/\Abytes=(\d*)-(\d*)\z/, header) do
      [_, "", ""] ->
        :whole

      [_, "", suffix] ->
        suffix_range(String.to_integer(suffix), size)

      [_, first, ""] ->
        bounded(String.to_integer(first), size - 1, size)

      [_, first, last] ->
        bounded(String.to_integer(first), min(String.to_integer(last), size - 1), size)

      nil ->
        :whole
    end
  end

  defp range(_absent_or_several, _size), do: :whole

  defp suffix_range(0, _size), do: :unsatisfiable
  defp suffix_range(length, size), do: bounded(max(size - length, 0), size - 1, size)

  defp bounded(first, last, size) when first < size and first <= last, do: {:ok, first, last}
  defp bounded(_first, _last, _size), do: :unsatisfiable

  defp gone(conn, type, fields) do
    Problem.send(conn, 410, Map.merge(%{type: Problem.type(type), title: type}, fields))
  end
end
