defmodule PluteusWeb.SubsonicConformanceTest do
  @moduledoc """
  What [OPENSUBSONIC] requires of every response, over a session in the order
  a client makes it: the handshake, then browsing, then a song.

  The required fields are the specification's own, per response type. A client
  reads them without asking whether this server happened to fill them in, so a
  response missing one is a defect here even where every other test passes.
  """

  use PluteusWeb.ConnCase, async: true

  import Pluteus.IngestFixtures

  alias Pluteus.Annotations
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Ingest.Place
  alias Pluteus.MusicFixtures
  alias Pluteus.Repo

  # [OPENSUBSONIC] responses/child, responses/albumid3, responses/artistid3.
  @child ~w(id isDir title mediaType bitDepth samplingRate channelCount)
  @album ~w(id name songCount duration created)
  @artist ~w(id name)

  setup %{conn: conn} do
    library = MusicFixtures.library!()

    %{"key" => key} =
      conn
      |> through_proxy("ada@example.test")
      |> post("/devices", %{"label" => "Symfonium"})
      |> json_response(201)

    %{conn: via_proxy(conn), key: key, library: library}
  end

  describe "the handshake a client makes before anything else" do
    test "ping, extensions and the music folders answer as the protocol says", context do
      ping = call(context, "ping", %{})

      assert ping["status"] == "ok"
      assert ping["version"] == "1.16.1"
      assert ping["openSubsonic"] == true
      assert is_binary(ping["type"]) and is_binary(ping["serverVersion"])

      extensions = call(context, "getOpenSubsonicExtensions", %{})["openSubsonicExtensions"]

      assert Enum.sort(Enum.map(extensions, & &1["name"])) ==
               ~w(apiKeyAuthentication formPost indexBasedQueue songLyrics)

      assert Enum.all?(extensions, &(&1["versions"] == [1]))

      folders = call(context, "getMusicFolders", %{})["musicFolders"]["musicFolder"]
      assert [%{"id" => id}] = folders
      assert is_integer(id), "a music folder's id is an int, not #{inspect(id)}"
    end

    test "a client asking for a newer protocol version is told the server must upgrade",
         context do
      assert error(context, "ping", %{"v" => "1.17.0"}) == 30
      assert error(context, "getAlbumList2", %{"v" => "2.0.0", "type" => "random"}) == 30

      assert call(context, "ping", %{"v" => "1.16.1"})["status"] == "ok"
      assert call(context, "ping", %{"v" => "1.15.0"})["status"] == "ok"
    end
  end

  describe "every response carries the fields its type requires" do
    test "songs, wherever a client meets them", context do
      album_id = context.library.albums["01 So What.flac"]
      song_id = context.library.songs["01 So What.flac"]

      songs =
        [
          call(context, "getSong", %{"id" => song_id})["song"],
          hd(call(context, "getAlbum", %{"id" => album_id})["album"]["song"]),
          hd(call(context, "getMusicDirectory", %{"id" => album_id})["directory"]["child"]),
          hd(call(context, "search3", %{"query" => "so what"})["searchResult3"]["song"]),
          hd(call(context, "getRandomSongs", %{"size" => "1"})["randomSongs"]["song"])
        ]

      for song <- songs, field <- @child do
        assert Map.has_key?(song, field), "a song is missing #{field}: #{inspect(song)}"
      end

      song = hd(songs)
      assert song["mediaType"] == "song"
      assert song["isDir"] == false
      assert song["isVideo"] == false
      assert song["channelCount"] == 1
      assert song["samplingRate"] == 44_100
      assert song["bitDepth"] == 16
      assert song["playCount"] == 0
    end

    test "albums and artists, in both the ID3 and the directory forms", context do
      album_id = context.library.albums["01 So What.flac"]

      albums = [
        call(context, "getAlbum", %{"id" => album_id})["album"],
        hd(
          call(context, "getAlbumList2", %{"type" => "alphabeticalByName"})["albumList2"]["album"]
        ),
        hd(call(context, "search3", %{"query" => "kind of blue"})["searchResult3"]["album"])
      ]

      for album <- albums, field <- @album do
        assert Map.has_key?(album, field), "an album is missing #{field}: #{inspect(album)}"
      end

      index = hd(call(context, "getArtists", %{})["artists"]["index"])

      for artist <- index["artist"], field <- @artist do
        assert Map.has_key?(artist, field), "an artist is missing #{field}"
      end

      artist = hd(index["artist"])
      assert Map.has_key?(call(context, "getArtist", %{"id" => artist["id"]})["artist"], "album")
    end

    test "a lossy song carries a bit depth all the same, as none", context do
      inbox = inbox!()
      drop!(inbox, "lossy/mixtape.mp3", media!(:mp3))
      inbox |> acquire_settled!(~U[2026-09-18 12:00:00.000000Z]) |> acquired()
      Place.place_due(inbox)
      Normalize.normalize_due()

      [acquisition] = Ingest.acquisitions_from("lossy/mixtape.mp3")

      song_id =
        Repo.get!(DigitalItem, acquisition.digital_item_id).manifestation_id

      song = call(context, "getSong", %{"id" => song_id})["song"]

      assert song["bitDepth"] == 0
      assert song["samplingRate"] > 0
      assert song["contentType"] == "audio/mpeg"
    end

    test "a song's measured tempo is its bpm", context do
      song_id = context.library.songs["01 So What.flac"]

      {:ok, derivation} =
        Annotations.record_derivation(%{
          tool: "pluteus-native",
          version: "1",
          input_id: song_id,
          parameters: %{},
          derived_at: DateTime.utc_now()
        })

      {:ok, _} =
        Annotations.annotate(%{
          target_id: song_id,
          body_type: "measurements",
          body: %{"tempo_bpm" => 117.45},
          derivation_id: derivation.id
        })

      assert call(context, "getSong", %{"id" => song_id})["song"]["bpm"] == 117
    end

    test "what the principal did with a song travels with it", context do
      song_id = context.library.songs["01 So What.flac"]

      call(context, "scrobble", %{"id" => song_id, "time" => "1757000000000"})
      call(context, "createBookmark", %{"id" => song_id, "position" => "42000"})
      call(context, "star", %{"id" => song_id})
      call(context, "setRating", %{"id" => song_id, "rating" => "5"})

      song = call(context, "getSong", %{"id" => song_id})["song"]

      assert song["playCount"] == 1
      assert song["played"] =~ "2025-09-04"
      assert song["bookmarkPosition"] == 42
      assert song["userRating"] == 5
      assert is_binary(song["starred"])
    end
  end

  describe "the responses a client reads its own data from" do
    test "a playlist, a bookmark, a queue and a now-playing entry carry their fields",
         context do
      song_id = context.library.songs["01 So What.flac"]
      other_id = context.library.songs["02 Freddie.flac"]

      playlist =
        call(context, "createPlaylist", %{"name" => "Evening", "songId" => song_id})["playlist"]

      for field <- ~w(id name songCount duration created changed) do
        assert Map.has_key?(playlist, field), "a playlist is missing #{field}"
      end

      call(context, "createBookmark", %{"id" => song_id, "position" => "61000"})
      [bookmark] = call(context, "getBookmarks", %{})["bookmarks"]["bookmark"]

      for field <- ~w(entry position username created changed) do
        assert Map.has_key?(bookmark, field), "a bookmark is missing #{field}"
      end

      assert bookmark["position"] == 61_000, "a bookmark's position is in milliseconds"
      assert bookmark["entry"]["bookmarkPosition"] == 61, "a song's is in seconds"

      call(context, "scrobble", %{"id" => other_id, "submission" => "false"})
      [entry] = call(context, "getNowPlaying", %{})["nowPlaying"]["entry"]

      for field <- ~w(username minutesAgo playerId) do
        assert Map.has_key?(entry, field), "a now-playing entry is missing #{field}"
      end

      assert is_integer(entry["playerId"]), "a player's id is an int"
    end

    test "a queue with entries names one of them current", context do
      song_id = context.library.songs["01 So What.flac"]
      other_id = context.library.songs["02 Freddie.flac"]

      get(
        context.conn,
        "/rest/savePlayQueue?id=#{song_id}&id=#{other_id}&apiKey=#{context.key}&f=json"
      )

      queue = call(context, "getPlayQueue", %{})["playQueue"]

      for field <- ~w(username changed changedBy entry) do
        assert Map.has_key?(queue, field), "a play queue is missing #{field}"
      end

      assert queue["current"] == song_id,
             "a queue saved with no current song still names where it is"

      assert call(context, "getPlayQueueByIndex", %{})["playQueueByIndex"]["currentIndex"] == 0
    end

    test "a timestamp is written to the second", context do
      song = call(context, "getSong", %{"id" => context.library.songs["01 So What.flac"]})["song"]

      assert song["created"] =~ ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/
    end
  end

  describe "a browser player reaches the bytes the way it builds URLs" do
    test "cover art and stream answer a plain GET with the key in the query", context do
      song_id = context.library.songs["01 So What.flac"]

      cover = get(context.conn, "/rest/getCoverArt", %{"id" => song_id, "apiKey" => context.key})
      assert cover.status == 200
      assert ["image/" <> _] = get_resp_header(cover, "content-type")

      streamed = get(context.conn, "/rest/stream", %{"id" => song_id, "apiKey" => context.key})
      assert streamed.status == 200
      assert get_resp_header(streamed, "accept-ranges") == ["bytes"]
      assert ["audio/flac"] = get_resp_header(streamed, "content-type")
    end
  end

  defp call(context, endpoint, params) do
    body = envelope(context, endpoint, params)
    assert body["status"] == "ok", "#{endpoint}: #{inspect(body["error"])}"
    body
  end

  defp error(context, endpoint, params) do
    body = envelope(context, endpoint, params)
    assert body["status"] == "failed"
    body["error"]["code"]
  end

  defp envelope(context, endpoint, params) do
    context.conn
    |> get("/rest/#{endpoint}", Map.merge(params, %{"apiKey" => context.key, "f" => "json"}))
    |> json_response(200)
    |> Map.fetch!("subsonic-response")
  end
end
