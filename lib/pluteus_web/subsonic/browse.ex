defmodule PluteusWeb.Subsonic.Browse do
  @moduledoc """
  The browsing endpoints of spec-07 §6.3: the one music folder, artists,
  albums and songs, the directory presentation of the same catalog, genres,
  cover art and lyrics.

  `getIndexes` and `getMusicDirectory` present the catalog as directories —
  artists, an artist's albums, an album's songs — naming nothing the
  filesystem holds (§6.4).
  """

  alias Pluteus.Ingest.Streams
  alias Pluteus.Music
  alias Pluteus.Music.Album
  alias Pluteus.Music.Song
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Generate
  alias Pluteus.Storage
  alias PluteusWeb.ContentController
  alias PluteusWeb.StoredBytes
  alias PluteusWeb.Subsonic.Request
  alias PluteusWeb.Subsonic.Response
  alias PluteusWeb.Subsonic.Shape

  @folder %{"id" => 1, "name" => "Music"}

  @endpoints ~w(getMusicFolders getIndexes getMusicDirectory getGenres getArtists getArtist
                getAlbum getSong getArtistInfo2 getAlbumInfo2 getCoverArt getLyricsBySongId)

  @spec endpoints() :: [String.t()]
  def endpoints, do: @endpoints

  @spec handle(String.t(), Plug.Conn.t()) :: Plug.Conn.t()
  def handle(endpoint, conn) do
    case answer(endpoint, conn) do
      {:ok, key, body} -> Response.ok(conn, key, body)
      {:error, code, message} -> Response.error(conn, code, message)
      %Plug.Conn{} = sent -> sent
    end
  end

  defp answer("getMusicFolders", _conn),
    do: {:ok, "musicFolders", %{"musicFolder" => [@folder]}}

  defp answer("getIndexes", conn) do
    library = Music.library(Request.profile(conn))
    context = Shape.context(conn, Shape.ids(library))

    {:ok, "indexes",
     %{
       "lastModified" => last_modified(library),
       "ignoredArticles" => "",
       "index" => Shape.index(Music.artists(library), &Shape.artist(&1, &2, context))
     }}
  end

  defp answer("getArtists", conn) do
    library = Music.library(Request.profile(conn))
    context = Shape.context(conn, Shape.ids(library))

    {:ok, "artists",
     %{
       "ignoredArticles" => "",
       "index" => Shape.index(Music.artists(library), &Shape.artist(&1, &2, context))
     }}
  end

  defp answer("getArtist", conn) do
    with {:ok, {artist, albums, context}} <- artist(conn) do
      {:ok, "artist",
       artist
       |> Shape.artist(albums, context)
       |> Map.put("album", Enum.map(albums, &Shape.album(&1, context, false)))}
    end
  end

  defp answer("getArtistInfo2", conn) do
    with {:ok, {artist, _albums, _context}} <- artist(conn) do
      {:ok, "artistInfo2", %{"musicBrainzId" => artist.musicbrainz_id}}
    end
  end

  defp answer("getMusicDirectory", conn) do
    with {:ok, id} <- Request.required(conn, "id") do
      case artist(conn) do
        {:ok, {artist, albums, context}} ->
          {:ok, "directory",
           %{
             "id" => artist.id,
             "name" => artist.name,
             "child" => Enum.map(albums, &Shape.album_child(&1, artist.id, context))
           }}

        {:error, _code, _message} ->
          album_directory(conn, id)
      end
    end
  end

  defp answer("getAlbum", conn) do
    with {:ok, album} <- album(conn) do
      {:ok, "album", Shape.album(album, Shape.context(conn, Shape.ids([album])), true)}
    end
  end

  # What the catalog holds about a release: its description companion as the
  # notes, and the MusicBrainz release its tracks are tagged with. Image URLs
  # are not given, since they would have to carry the client's key; a client
  # asks getCoverArt by the album's coverArt.
  defp answer("getAlbumInfo2", conn) do
    with {:ok, album} <- album(conn) do
      notes =
        case Music.companion(album.id, "description") do
          nil -> nil
          asset -> text(Storage.read(asset.location), album.id)
        end

      {:ok, "albumInfo", %{"notes" => notes, "musicBrainzId" => release_identifier(album)}}
    end
  end

  defp answer("getSong", conn) do
    with {:ok, {song, album}} <- song(conn) do
      {:ok, "song", Shape.song(song, album, Shape.context(conn, [song.id]))}
    end
  end

  defp answer("getGenres", conn) do
    library = Music.library(Request.profile(conn))

    genres =
      for album <- library,
          song <- album.songs,
          genre <- Music.genres(song),
          do: {genre, album.id}

    {:ok, "genres",
     %{
       "genre" =>
         genres
         |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
         |> Enum.sort_by(&elem(&1, 0))
         |> Enum.map(fn {genre, album_ids} ->
           %{
             "value" => genre,
             "songCount" => length(album_ids),
             "albumCount" => album_ids |> Enum.uniq() |> length()
           }
         end)
     }}
  end

  defp answer("getCoverArt", conn) do
    with {:ok, id} <- Request.id(conn, "id") do
      profile = Request.profile(conn)

      case Music.album(id, profile) do
        %Album{} = album -> cover(conn, album, album.songs)
        nil -> song_cover(conn, id, profile)
      end
    end
  end

  defp answer("getLyricsBySongId", conn) do
    with {:ok, {song, album}} <- song(conn) do
      lyrics =
        case Music.companion(song.id, "lyrics") do
          nil -> []
          asset -> [structured(Storage.read(asset.location), song, album)]
        end

      {:ok, "lyricsList", %{"structuredLyrics" => lyrics}}
    end
  end

  # --- Lookups ------------------------------------------------------------------

  defp artist(conn) do
    with {:ok, id} <- Request.required(conn, "id") do
      case find_artist(Music.library(Request.profile(conn)), id) do
        {artist, albums} -> {:ok, {artist, albums, Shape.context(conn, Shape.ids(albums))}}
        nil -> Request.not_found(id)
      end
    end
  end

  defp find_artist(library, id),
    do: Enum.find(Music.artists(library), fn {artist, _albums} -> artist.id == id end)

  defp album(conn) do
    with {:ok, id} <- Request.id(conn, "id") do
      case Music.album(id, Request.profile(conn)) do
        nil -> Request.not_found(id)
        album -> {:ok, album}
      end
    end
  end

  defp song(conn) do
    with {:ok, id} <- Request.id(conn, "id") do
      case Music.song(id, Request.profile(conn)) do
        nil -> Request.not_found(id)
        found -> {:ok, found}
      end
    end
  end

  defp album_directory(conn, id) do
    with {:ok, album} <- album(conn) do
      context = Shape.context(conn, Shape.ids([album]))

      {:ok, "directory",
       %{
         "id" => album.id,
         "name" => album.name,
         "parent" => album.artists |> List.first() |> then(&(&1 && &1.id)),
         "child" => Enum.map(album.songs, &Shape.song(&1, album, context))
       }}
    end
    |> case do
      {:error, 70, _message} -> Request.not_found(id)
      other -> other
    end
  end

  defp last_modified(library) do
    library
    |> Enum.flat_map(&[&1.created | Enum.map(&1.songs, fn song -> song.created end)])
    |> Enum.max(DateTime, fn -> ~U[1970-01-01 00:00:00Z] end)
    |> DateTime.to_unix(:millisecond)
  end

  # --- Cover art (§6.4) ---------------------------------------------------------

  # The cover-art companion linked to the release, or else the picture embedded
  # in the first of the songs that carries one.
  #
  # §6.7's integer `size` is the one dimension any surface accepts, and [spec-10]
  # §11.1 has it accepted by translation rather than by widening: it maps to the
  # smallest profile at or above it, and the response names what it served. A client
  # here has no retry affordance and cannot read a 202, so the artefact is generated
  # while it waits rather than queued behind it.
  defp cover(conn, %Album{} = album, songs) do
    case Music.companion(album.id, "cover_art") do
      nil ->
        case Enum.find_value(songs, &embedded_picture/1) do
          nil -> Request.not_found(album.id)
          {media_type, bytes} -> send_picture(conn, media_type, bytes)
        end

      asset ->
        graded(conn, asset)
    end
  end

  defp graded(conn, asset) do
    profile =
      conn |> Request.optional("size") |> requested_width() |> Presentation.profile_for_size()

    name = Map.fetch!(profile, "name")

    case held_or_generated(asset.id, name) do
      {:ok, artefact} ->
        {:ok, served} = Presentation.serve(artefact)

        conn
        |> Plug.Conn.put_resp_header("presentation-profile", name)
        |> StoredBytes.send_stored(served.location,
          content_type: served.media_type,
          etag: served.digest
        )

      :none ->
        # Nothing could be made of these bytes. The cover as stored is still the
        # cover, and §17.1 makes the absence of a derivative not an error.
        ContentController.serve(conn, asset)
    end
  end

  defp held_or_generated(subject_id, profile) do
    case Presentation.get(subject_id, profile) do
      %Presentation.Asset{} = held ->
        {:ok, held}

      nil ->
        case Generate.run(subject_id, profile) do
          {:ok, made} -> {:ok, made}
          _refused_or_failed -> :none
        end
    end
  end

  # A size that is not a positive integer names no width, and the default profile
  # answers. §6.7 does not make a malformed size an error, and refusing one would
  # deny a client its cover over a query string it can no longer change.
  defp requested_width(nil), do: nil

  defp requested_width(size) when is_binary(size) do
    case Integer.parse(size) do
      {width, ""} when width > 0 -> width
      _not_a_width -> nil
    end
  end

  defp requested_width(size) when is_integer(size) and size > 0, do: size
  defp requested_width(_not_a_width), do: nil

  defp song_cover(conn, id, profile) do
    case Music.song(id, profile) do
      {song, album} -> cover(conn, album, [song])
      nil -> Request.not_found(id)
    end
  end

  # The attached picture is copied out of the acquired original as it is
  # stored, not re-encoded.
  defp embedded_picture(%Song{original: nil}), do: nil

  defp embedded_picture(%Song{original: original, probe: probe}) do
    stream =
      Enum.find(probe["streams"] || [], &(get_in(&1, ["disposition", "attached_pic"]) == 1))

    if stream do
      {bytes, 0} =
        System.cmd("ffmpeg", [
          "-v",
          "error",
          "-i",
          Storage.path(original.location),
          "-map",
          "0:#{stream["index"]}",
          "-c",
          "copy",
          "-f",
          "image2pipe",
          "-"
        ])

      {picture_type(stream["codec_name"]), bytes}
    end
  end

  defp picture_type("mjpeg"), do: "image/jpeg"
  defp picture_type("png"), do: "image/png"
  defp picture_type(_codec), do: "application/octet-stream"

  defp send_picture(conn, media_type, bytes) do
    conn
    |> Plug.Conn.put_resp_content_type(media_type, nil)
    |> Plug.Conn.send_resp(200, bytes)
  end

  defp release_identifier(album) do
    Enum.find_value(album.songs, fn song ->
      song.probe |> Streams.tags() |> Streams.release_identifiers() |> List.first()
    end)
  end

  defp text(bytes, id) do
    unless String.valid?(bytes), do: raise(ArgumentError, "the description of #{id} is not UTF-8")
    String.trim(bytes)
  end

  # --- Lyrics (§6.4) ------------------------------------------------------------

  # An LRC companion: `[mm:ss.xx]` stamps make its lines synchronized, and a
  # line may carry several. Tags such as `[ar:…]` describe the file and are not
  # lines.
  defp structured(text, song, album) do
    unless String.valid?(text), do: raise(ArgumentError, "lyrics of #{song.id} are not UTF-8")

    lines =
      text
      |> String.split(~r/\R/)
      |> Enum.flat_map(&lyric_line/1)

    synced = Enum.any?(lines, &Map.has_key?(&1, "start"))

    %{
      "lang" => "und",
      "synced" => synced,
      "displayTitle" => song.title,
      "displayArtist" => Enum.map_join(song.artists, ", ", & &1.name),
      "offset" => 0,
      "line" =>
        if(synced,
          do: lines |> Enum.filter(&Map.has_key?(&1, "start")) |> Enum.sort_by(& &1["start"]),
          else: lines
        )
    }
    |> Map.put("displayAlbum", album.name)
  end

  defp lyric_line(line) do
    stamps = Regex.scan(~r/\[(\d+):(\d{2})(?:[.:](\d{1,3}))?\]/, line)
    text = line |> String.replace(~r/\[[^\]]*\]/, "") |> String.trim()

    cond do
      stamps != [] ->
        Enum.map(stamps, fn [_, minutes, seconds | fraction] ->
          %{"start" => milliseconds(minutes, seconds, fraction), "value" => text}
        end)

      Regex.match?(~r/\A\[[a-z]+:/i, line) ->
        []

      text != "" ->
        [%{"value" => text}]

      true ->
        []
    end
  end

  defp milliseconds(minutes, seconds, fraction) do
    fraction_ms =
      case fraction do
        [] -> 0
        [""] -> 0
        [digits] -> digits |> String.pad_trailing(3, "0") |> String.to_integer()
      end

    (String.to_integer(minutes) * 60 + String.to_integer(seconds)) * 1000 + fraction_ms
  end
end
