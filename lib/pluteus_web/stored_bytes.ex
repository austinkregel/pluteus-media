defmodule PluteusWeb.StoredBytes do
  @moduledoc """
  Bytes from primary storage, with a byte range where one is asked for
  (spec-07 §4.4).

  A single range is honoured with `206 Partial Content`, as a player seeking asks
  for it; a range beyond the end is `416`. A request naming more than one range is
  served whole, which HTTP permits and which no player seeking needs otherwise.

  Nothing is transformed here. An asset's bytes are served as stored, a derivative's
  as generated, and a transcode is spec-08's.
  """

  import Plug.Conn

  alias Pluteus.Storage

  @doc """
  Serves what lies at a storage location.

  `content_type` and `etag` are the caller's, because what identifies a version
  differs by what is being served: an asset's digest is its own, and a derivative's
  is the digest of the bytes generated.
  """
  @spec send_stored(Plug.Conn.t(), String.t(), keyword()) :: Plug.Conn.t()
  def send_stored(conn, location, opts) do
    path = Storage.path(location)
    size = File.stat!(path).size

    conn =
      conn
      |> put_resp_content_type(Keyword.fetch!(opts, :content_type), nil)
      |> put_resp_header("accept-ranges", "bytes")
      |> put_resp_header("etag", ~s("#{Keyword.fetch!(opts, :etag)}"))

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
end
