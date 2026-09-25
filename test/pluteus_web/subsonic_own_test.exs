defmodule PluteusWeb.SubsonicOwnTest do
  @moduledoc """
  The requesting principal's own data on the OpenSubsonic surface: spec-07
  §6.5, §6.6 and criteria 5, 10, 18 and 19.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Consumption
  alias Pluteus.Events
  alias Pluteus.Lifecycle
  alias Pluteus.MusicFixtures
  alias Pluteus.Principals

  @subject "ada@example.test"

  setup %{conn: conn} do
    library = MusicFixtures.library!()

    %{"key" => key, "device" => %{"id" => device}} =
      conn
      |> through_proxy(@subject)
      |> post("/devices", %{"label" => "Symfonium"})
      |> json_response(201)

    {:ok, other} = Principals.create_principal(%{role: "member"})

    %{
      conn: via_proxy(conn),
      key: key,
      device: device,
      ada: Principals.principal_for(issuer(), @subject),
      other: other,
      album: library.albums["01 So What.flac"],
      loose: library.songs["untitled.wav"],
      so_what: library.songs["01 So What.flac"],
      freddie: library.songs["02 Freddie.flac"],
      artist_id: library.artist_id
    }
  end

  describe "stars and ratings" do
    test "star takes repeated songs, albums and artists, and unstar removes them", context do
      artist_id = context.artist_id

      ok(
        context,
        "star?id=#{context.so_what}&id=#{context.freddie}&albumId=#{context.album}&artistId=#{artist_id}"
      )

      assert context.ada.id |> Consumption.starred() |> Enum.map(& &1.res_id) |> Enum.sort() ==
               Enum.sort([context.so_what, context.freddie, context.album, artist_id])

      ok(context, "unstar?id=#{context.freddie}")
      refute context.freddie in Enum.map(Consumption.starred(context.ada.id), & &1.res_id)
      assert Consumption.starred(context.other.id) == []
    end

    test "an artist the tags alone named is starred and rated, as any res is", context do
      ok(context, "star?artistId=#{context.artist_id}")
      ok(context, "setRating?id=#{context.artist_id}&rating=5")

      assert Enum.map(Consumption.starred(context.ada.id), & &1.res_id) == [context.artist_id]

      assert Consumption.ratings(context.ada.id, [context.artist_id]) ==
               %{context.artist_id => 5}
    end

    test "an unknown target stars nothing", context do
      assert code(context, "star?id=#{context.so_what}&id=#{UUIDv7.generate()}") == 70
      assert Consumption.starred(context.ada.id) == []

      assert code(context, "star?artistId=#{UUIDv7.generate()}") == 70
      assert code(context, "star") == 10
    end

    test "a rating is set, shown, and cleared with zero", context do
      ok(context, "setRating?id=#{context.so_what}&rating=4")
      assert Consumption.ratings(context.ada.id, [context.so_what]) == %{context.so_what => 4}
      assert song(context, context.so_what)["userRating"] == 4

      ok(context, "setRating?id=#{context.so_what}&rating=0")
      assert Consumption.ratings(context.ada.id, [context.so_what]) == %{}

      assert code(context, "setRating?id=#{context.so_what}&rating=6") == 0
      assert code(context, "setRating?id=#{context.so_what}") == 10
    end

    test "another principal's star, rating, plays or bookmark are never shown", context do
      {:ok, other_device} = Principals.bind_device(context.other.id, "tv")
      {:ok, _} = Consumption.star(context.other.id, context.so_what)
      {:ok, _} = Consumption.rate(context.other.id, context.so_what, 5)
      {:ok, _} = Consumption.played(context.other.id, other_device.id, context.so_what)

      {:ok, _} =
        Consumption.bookmark(context.other.id, context.so_what, other_device.id, 90_000, nil)

      shown = song(context, context.so_what)

      refute Map.has_key?(shown, "starred")
      refute Map.has_key?(shown, "userRating")
      refute Map.has_key?(shown, "played")
      refute Map.has_key?(shown, "bookmarkPosition")
      assert shown["playCount"] == 0
    end
  end

  describe "5. scrobble records the key's principal's plays" do
    test "a submission is a play event; without one it is what is playing now", context do
      ok(context, "scrobble?id=#{context.so_what}&submission=false")

      assert [%{device_id: device, res_id: so_what}] = Consumption.now_playing(context.ada.id)
      assert {device, so_what} == {context.device, context.so_what}
      assert Events.for_principal(context.ada.id) == []

      ok(
        context,
        "scrobble?id=#{context.so_what}&id=#{context.freddie}&time=1757000000000&time=1757000300000"
      )

      played = Events.for_principal(context.ada.id)

      assert Enum.map(played, &{&1.res_id, &1.type}) |> Enum.sort() ==
               Enum.sort([{context.so_what, "played"}, {context.freddie, "played"}])

      assert DateTime.to_unix(
               Enum.find(played, &(&1.res_id == context.so_what)).occurred_at,
               :millisecond
             ) ==
               1_757_000_000_000

      assert Consumption.now_playing(context.ada.id) == []
      assert Events.for_principal(context.other.id) == []
    end
  end

  describe "playlists" do
    test "created, listed, read, edited by shown position and deleted", context do
      created =
        call(
          context,
          "createPlaylist?name=Evening&songId=#{context.so_what}&songId=#{context.freddie}&songId=#{context.loose}"
        )["playlist"]

      assert {created["owner"], created["public"], created["songCount"]} ==
               {context.ada.id, false, 3}

      id = created["id"]

      assert [%{"id" => ^id, "name" => "Evening"}] =
               call(context, "getPlaylists")["playlists"]["playlist"]

      ok(
        context,
        "updatePlaylist?playlistId=#{id}&name=Night&songIndexToRemove=0&songIdToAdd=#{context.so_what}"
      )

      playlist = call(context, "getPlaylist?id=#{id}")["playlist"]
      assert playlist["name"] == "Night"

      assert Enum.map(playlist["entry"], & &1["id"]) == [
               context.freddie,
               context.loose,
               context.so_what
             ]

      ok(context, "deletePlaylist?id=#{id}")
      assert call(context, "getPlaylists")["playlists"] == %{"playlist" => []}
    end

    test "createPlaylist with a playlistId replaces its songs", context do
      {:ok, playlist} = Consumption.create_playlist(context.ada.id, "Evening", [context.so_what])
      call(context, "createPlaylist?playlistId=#{playlist.id}&songId=#{context.freddie}")

      assert Enum.map(
               call(context, "getPlaylist?id=#{playlist.id}")["playlist"]["entry"],
               & &1["id"]
             ) ==
               [context.freddie]
    end

    test "a recycled song is left out, and positions are counted among what is shown", context do
      {:ok, playlist} =
        Consumption.create_playlist(context.ada.id, "Evening", [
          context.so_what,
          context.freddie,
          context.loose
        ])

      {:ok, recycling} = Lifecycle.recycle(context.so_what, context.ada.id)

      shown = call(context, "getPlaylist?id=#{playlist.id}")["playlist"]
      assert Enum.map(shown["entry"], & &1["id"]) == [context.freddie, context.loose]
      assert shown["songCount"] == 2

      ok(context, "updatePlaylist?playlistId=#{playlist.id}&songIndexToRemove=0")
      {:ok, _} = Lifecycle.restore(recycling.id)

      assert Enum.map(
               call(context, "getPlaylist?id=#{playlist.id}")["playlist"]["entry"],
               & &1["id"]
             ) ==
               [context.so_what, context.loose]
    end

    test "a playlist naming no live song is refused and not made", context do
      assert code(context, "createPlaylist?name=Evening&songId=#{UUIDv7.generate()}") == 70
      assert Consumption.playlists(context.ada.id) == []
      assert code(context, "createPlaylist") == 10
    end

    test "form posts carry repeated values", context do
      response =
        context.conn
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post(
          "/rest/createPlaylist",
          "apiKey=#{context.key}&f=json&name=Evening&songId=#{context.so_what}&songId=#{context.freddie}"
        )
        |> json_response(200)

      assert response["subsonic-response"]["playlist"]["songCount"] == 2
    end
  end

  describe "19. Another principal's playlist is error 70, and none can be made public" do
    test "reading, changing, replacing and deleting another's playlist are each 70", context do
      {:ok, theirs} = Consumption.create_playlist(context.other.id, "Theirs", [context.so_what])

      assert code(context, "getPlaylist?id=#{theirs.id}") == 70
      assert code(context, "updatePlaylist?playlistId=#{theirs.id}&name=Mine") == 70

      assert code(context, "createPlaylist?playlistId=#{theirs.id}&songId=#{context.freddie}") ==
               70

      assert code(context, "deletePlaylist?id=#{theirs.id}") == 70
      assert call(context, "getPlaylists")["playlists"] == %{"playlist" => []}

      assert Consumption.playlist(context.other.id, theirs.id).name == "Theirs"
    end

    test "public is refused with 50, and another's list is not served", context do
      {:ok, mine} = Consumption.create_playlist(context.ada.id, "Mine", [])

      assert code(context, "updatePlaylist?playlistId=#{mine.id}&public=true") == 50
      assert code(context, "getPlaylists?username=#{context.other.id}") == 50
    end
  end

  describe "the play queue" do
    test "saved by song, read back with its current song and position", context do
      ok(
        context,
        "savePlayQueue?id=#{context.so_what}&id=#{context.freddie}&current=#{context.freddie}&position=4200"
      )

      queue = call(context, "getPlayQueue")["playQueue"]
      assert Enum.map(queue["entry"], & &1["id"]) == [context.so_what, context.freddie]

      assert {queue["current"], queue["position"], queue["changedBy"], queue["username"]} ==
               {context.freddie, 4200, "Symfonium", context.ada.id}

      assert Consumption.play_queue(context.other.id) == nil
    end

    test "saved and read by index, which is exact where a song repeats", context do
      ok(
        context,
        "savePlayQueueByIndex?id=#{context.so_what}&id=#{context.freddie}&id=#{context.so_what}&currentIndex=2&position=10"
      )

      queue = call(context, "getPlayQueueByIndex")["playQueueByIndex"]
      assert queue["currentIndex"] == 2

      assert Enum.map(queue["entry"], & &1["id"]) == [
               context.so_what,
               context.freddie,
               context.so_what
             ]

      assert code(context, "savePlayQueueByIndex?id=#{context.so_what}&currentIndex=1") == 0
      assert code(context, "savePlayQueue?id=#{context.so_what}&current=#{context.freddie}") == 0
    end

    test "a current song that repeats is its first place", context do
      ok(
        context,
        "savePlayQueue?id=#{context.so_what}&id=#{context.freddie}&id=#{context.so_what}&current=#{context.so_what}"
      )

      assert call(context, "getPlayQueueByIndex")["playQueueByIndex"]["currentIndex"] == 0
    end

    test "an empty save clears it", context do
      ok(context, "savePlayQueue?id=#{context.so_what}")
      ok(context, "savePlayQueue")
      assert call(context, "getPlayQueue")["playQueue"] == %{"entry" => []}
    end
  end

  describe "bookmarks" do
    test "created, listed with the song, and deleted", context do
      ok(context, "createBookmark?id=#{context.so_what}&position=61000&comment=the%20solo")

      assert [bookmark] = call(context, "getBookmarks")["bookmarks"]["bookmark"]

      assert {bookmark["position"], bookmark["comment"], bookmark["entry"]["id"]} ==
               {61_000, "the solo", context.so_what}

      ok(context, "deleteBookmark?id=#{context.so_what}")
      assert call(context, "getBookmarks")["bookmarks"] == %{"bookmark" => []}
      assert code(context, "deleteBookmark?id=#{context.so_what}") == 70
    end

    test "another principal's bookmark is neither listed nor deleted", context do
      # The device is the other principal's own: the composite foreign key on
      # `resume_positions` admits no other (spec-01 §11.4).
      {:ok, theirs} = Principals.bind_device(context.other.id, "their tv")

      {:ok, _} = Consumption.bookmark(context.other.id, context.so_what, theirs.id, 5_000, nil)

      assert call(context, "getBookmarks")["bookmarks"] == %{"bookmark" => []}
      assert code(context, "deleteBookmark?id=#{context.so_what}") == 70
      assert [_] = Consumption.bookmarks(context.other.id)
      assert code(context, "createBookmark?id=#{context.so_what}") == 10
    end
  end

  describe "getUser" do
    test "answers for the requesting principal and no other", context do
      user = call(context, "getUser?username=#{context.ada.id}")["user"]

      assert {user["username"], user["streamRole"], user["adminRole"], user["folder"]} ==
               {context.ada.id, true, false, [1]}

      assert code(context, "getUser?username=#{context.other.id}") == 50
      assert code(context, "getUser") == 10
    end
  end

  defp song(context, id), do: call(context, "getSong?id=#{id}")["song"]

  defp ok(context, path), do: call(context, path)

  defp call(context, path) do
    body = envelope(context, path)
    assert body["status"] == "ok", inspect(body["error"])
    body
  end

  defp code(context, path) do
    body = envelope(context, path)
    assert body["status"] == "failed"
    body["error"]["code"]
  end

  defp envelope(context, path) do
    separator = if String.contains?(path, "?"), do: "&", else: "?"

    context.conn
    |> get("/rest/#{path}#{separator}apiKey=#{context.key}&f=json")
    |> json_response(200)
    |> Map.fetch!("subsonic-response")
  end
end
