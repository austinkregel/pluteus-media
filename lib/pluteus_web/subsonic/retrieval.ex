defmodule PluteusWeb.Subsonic.Retrieval do
  @moduledoc """
  `stream` and `download` (spec-07 §6.7).

  `stream` serves the song's normalized master as stored, honouring byte
  ranges; until spec-08, `format`, `maxBitRate` and `estimateContentLength`
  change nothing, and the content type says what was served. `download`
  serves the acquired original, the bytes as they arrived.

  A track of a release held in one file has no digital item of its own.
  Serving it means cutting its extent from the release's master, which is a
  transcode, and waits for spec-08; until then both answer error 0 and say so.
  """

  alias Pluteus.Music
  alias PluteusWeb.ContentController
  alias PluteusWeb.Subsonic.Request
  alias PluteusWeb.Subsonic.Response

  @endpoints ~w(stream download)

  @behaviour PluteusWeb.Subsonic.Surface

  @impl true
  @spec endpoints() :: [String.t()]
  def endpoints, do: @endpoints

  # Streaming, which spec-08 §14.1 makes a grant recorded with the credential and
  # checked on every request. Not also `read_catalog`: resolving the song is how
  # the asset is found, so a credential that may stream but could not resolve one
  # could not stream anything. `download` has no other home among the three names
  # the specs give, and it is the one classification they do not settle.
  @impl true
  @spec operations(String.t()) :: [atom()]
  def operations(endpoint) when endpoint in @endpoints, do: [:stream]

  @impl true
  @spec handle(String.t(), Plug.Conn.t()) :: Plug.Conn.t()
  def handle(endpoint, conn) do
    with {:ok, id} <- Request.id(conn, "id"),
         {:ok, song} <- song(conn, id),
         {:ok, asset} <- asset(endpoint, song) do
      ContentController.serve(conn, asset)
    else
      {:error, code, message} -> Response.error(conn, code, message)
    end
  end

  defp song(conn, id) do
    case Music.song(id, Request.profile(conn)) do
      {song, _album} -> {:ok, song}
      nil -> Request.not_found(id)
    end
  end

  defp asset(_endpoint, %{extent: {_start, _end}}) do
    {:error, 0,
     "This song is cut from a release held in one file; serving it is a transcode, " <>
       "which this server does not yet provide"}
  end

  defp asset("stream", %{master: nil, id: id}),
    do: {:error, 0, "Song #{id} has no normalized master yet"}

  defp asset("stream", %{master: master}), do: {:ok, master}

  defp asset("download", %{original: nil, id: id}),
    do: {:error, 0, "Song #{id} holds no acquired original"}

  defp asset("download", %{original: original}), do: {:ok, original}
end
