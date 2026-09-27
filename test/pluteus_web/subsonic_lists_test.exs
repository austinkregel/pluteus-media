defmodule PluteusWeb.SubsonicListsTest do
  @moduledoc """
  Lists and search on the OpenSubsonic surface: spec-07 §6.3, §6.5 and
  criterion 18.
  """

  use PluteusWeb.ConnCase, async: true

  import Pluteus.IngestFixtures

  alias Pluteus.Catalog
  alias Pluteus.Consumption
  alias Pluteus.Ingest.Place
  alias Pluteus.MusicFixtures
  alias Pluteus.PrincipalFixtures
  alias Pluteus.Principals
  alias Pluteus.Principals.Device
  alias Pluteus.Repo

  @subject "ada@example.test"

  setup %{conn: conn} do
    library = MusicFixtures.library!()

    %{"key" => key, "device" => %{"id" => phone}} =
      conn
      |> through_proxy(@subject)
      |> post("/devices", %{"label" => "phone"})
      |> json_response(201)

    {:ok, other} = Principals.create_principal(%{role: "member"})
    tv = PrincipalFixtures.a_device(other.id, "tv")

    %{
      conn: via_proxy(conn),
      key: key,
      phone: phone,
      tv: tv.id,
      ada: Principals.principal_for(issuer(), @subject),
      other: other,
      album: library.albums["01 So What.flac"],
      loose: library.albums["untitled.wav"],
      so_what: library.songs["01 So What.flac"],
      freddie: library.songs["02 Freddie.flac"],
      artist: library.artist,
      artist_id: library.artist_id
    }
  end

  describe "album lists" do
    test "by name, by artist, newest, by year and by genre", context do
      assert ids(context, "alphabeticalByName") == [context.album, context.loose]
      assert ids(context, "alphabeticalByArtist") == [context.loose, context.album]

      newest = list(context, %{"type" => "newest"})
      created = Enum.map(newest, & &1["created"])
      assert created == Enum.sort(created, :desc)
      assert [_, _] = newest

      assert ids(context, "byYear", %{"fromYear" => "1950", "toYear" => "1960"}) ==
               [context.album]

      assert ids(context, "byYear", %{"fromYear" => "1960", "toYear" => "1950"}) ==
               [context.album]

      assert ids(context, "byYear", %{"fromYear" => "1960", "toYear" => "1970"}) == []
      assert ids(context, "byGenre", %{"genre" => "Jazz"}) == [context.album]
      assert ids(context, "random") |> Enum.sort() == Enum.sort([context.album, context.loose])
    end

    test "size and offset page the list", context do
      assert ids(context, "alphabeticalByName", %{"size" => "1"}) == [context.album]

      assert ids(context, "alphabeticalByName", %{"size" => "1", "offset" => "1"}) == [
               context.loose
             ]
    end

    test "the child form names the album's artist as its parent", context do
      [album | _] =
        call(context, "getAlbumList", %{"type" => "alphabeticalByName"})["albumList"]["album"]

      assert album["isDir"] == true
      assert album["parent"] == context.artist_id
    end

    test "a type, a year range or a genre missing is 10, and an unknown type 0", context do
      assert error(context, "getAlbumList2", %{}) == 10
      assert error(context, "getAlbumList2", %{"type" => "byYear", "fromYear" => "1950"}) == 10
      assert error(context, "getAlbumList2", %{"type" => "byGenre"}) == 10
      assert error(context, "getAlbumList2", %{"type" => "loudest"}) == 0
      assert error(context, "getAlbumList2", %{"type" => "random", "size" => "501"}) == 0
    end

    test "another music folder is not found", context do
      assert error(context, "getAlbumList2", %{"type" => "random", "musicFolderId" => "7"}) == 70

      assert ids(context, "alphabeticalByName", %{"musicFolderId" => "1"}) ==
               [context.album, context.loose]
    end
  end

  describe "by year" do
    test "an ascending range lists oldest first, a descending one newest first", context do
      inbox = inbox!()

      drop!(
        inbox,
        "ESP/01.flac",
        media!(:flac,
          tags: %{"album" => "E.S.P.", "album_artist" => "Miles Davis", "date" => "1965"}
        )
      )

      inbox |> acquire_settled!(~U[2026-09-18 12:00:00.000000Z]) |> acquired()
      Place.place_due(inbox)

      [older, newer] = ids(context, "byYear", %{"fromYear" => "1950", "toYear" => "1970"})
      assert older == context.album

      assert ids(context, "byYear", %{"fromYear" => "1970", "toYear" => "1950"}) ==
               [newer, older]
    end
  end

  describe "18. No list reflects another principal's consumption" do
    test "starred and highest read the principal's own stars and ratings", context do
      {:ok, _} = Consumption.star(context.other.id, context.loose)
      {:ok, _} = Consumption.rate(context.other.id, context.loose, 5)
      assert ids(context, "starred") == []
      assert ids(context, "highest") == []

      {:ok, _} = Consumption.star(context.ada.id, context.album)
      {:ok, _} = Consumption.rate(context.ada.id, context.album, 2)
      assert ids(context, "starred") == [context.album]
      assert ids(context, "highest") == [context.album]
    end

    test "frequent and recent count and order the principal's own plays", context do
      for _ <- 1..3,
          do: {:ok, _} = Consumption.played(context.other.id, context.tv, context.so_what)

      assert ids(context, "frequent") == []
      assert ids(context, "recent") == []

      loose_song = hd(call(context, "getAlbum", %{"id" => context.loose})["album"]["song"])["id"]

      {:ok, _} =
        Consumption.played(
          context.ada.id,
          context.phone,
          context.so_what,
          ~U[2026-09-01 10:00:00Z]
        )

      {:ok, _} =
        Consumption.played(
          context.ada.id,
          context.phone,
          context.freddie,
          ~U[2026-09-01 10:10:00Z]
        )

      {:ok, _} =
        Consumption.played(context.ada.id, context.phone, loose_song, ~U[2026-09-02 10:00:00Z])

      assert ids(context, "frequent") == [context.album, context.loose]
      assert ids(context, "recent") == [context.loose, context.album]
    end

    test "now playing is the principal's own sessions", context do
      :ok = Consumption.playing(context.other.id, context.tv, context.freddie)
      assert call(context, "getNowPlaying", %{})["nowPlaying"] == %{"entry" => []}

      :ok = Consumption.playing(context.ada.id, context.phone, context.so_what)

      assert [entry] = call(context, "getNowPlaying", %{})["nowPlaying"]["entry"]

      player = Repo.get!(Device, context.phone).player_number

      assert {entry["id"], entry["username"], entry["playerId"], entry["playerName"]} ==
               {context.so_what, context.ada.id, player, "phone"}

      assert is_integer(player), "a player's id is an int, not #{inspect(player)}"
    end

    test "starred lists hold the principal's own artists, albums and songs", context do
      {:ok, %{res: agent}} = Catalog.create_named_res(:person, "Miles Davis")

      {_count, _} =
        Pluteus.Repo.update_all(Pluteus.Catalog.Credit,
          set: [agent_id: agent.id, agent_kind: :person]
        )

      {:ok, _} = Consumption.star(context.other.id, context.freddie)

      for id <- [agent.id, context.album, context.so_what],
          do: {:ok, _} = Consumption.star(context.ada.id, id)

      starred = call(context, "getStarred2", %{})["starred2"]

      assert Enum.map(starred["artist"], & &1["id"]) == [agent.id]
      assert Enum.map(starred["album"], & &1["id"]) == [context.album]
      assert Enum.map(starred["song"], & &1["id"]) == [context.so_what]
      assert hd(starred["song"])["starred"]

      assert Enum.map(call(context, "getStarred", %{})["starred"]["album"], & &1["isDir"]) ==
               [true]
    end
  end

  describe "songs by genre, and at random" do
    test "each keeps to the genre asked for", context do
      assert song_ids(context, "getSongsByGenre", "songsByGenre", %{"genre" => "Modal"}) ==
               [context.so_what]

      assert song_ids(context, "getRandomSongs", "randomSongs", %{"genre" => "Jazz"}) ==
               [context.freddie]

      assert context
             |> song_ids("getRandomSongs", "randomSongs", %{
               "fromYear" => "1950",
               "toYear" => "1960"
             })
             |> Enum.sort() == Enum.sort([context.so_what, context.freddie])

      assert error(context, "getSongsByGenre", %{}) == 10
    end
  end

  describe "search" do
    test "matches albums, songs and artists by any name they carry", context do
      assert search(context, "blue")["album"] |> Enum.map(& &1["id"]) == [context.album]
      assert search(context, "blue")["artist"] == []
      assert search(context, "FREDDIE")["song"] |> Enum.map(& &1["id"]) == [context.freddie]

      assert search(context, "miles")["artist"] |> Enum.map(& &1["id"]) == [context.artist_id]

      # A person searching for the band means its records: the album is called
      # "Kind of Blue" and no song is called "Miles Davis".
      miles = search(context, "miles")
      assert Enum.map(miles["album"], & &1["id"]) == [context.album]

      assert Enum.sort(Enum.map(miles["song"], & &1["id"])) ==
               Enum.sort([context.so_what, context.freddie])

      {:ok, _} =
        Catalog.create_nomen(%{
          res_id: context.album,
          nomen_string: "Blaue Art",
          provenance: :automatic
        })

      assert search(context, "blaue")["album"] |> Enum.map(& &1["name"]) == ["Kind of Blue"]
    end

    test "an empty query matches everything, and counts page it", context do
      all = search(context, "")
      assert [_, _] = all["album"]
      assert [_, _, _] = all["song"]

      assert search(context, ~s(""), %{"songCount" => "1", "songOffset" => "2"})["song"] ==
               [Enum.at(all["song"], 2)]
    end

    test "a percent sign is a character, not a wildcard", context do
      assert search(context, "%")["album"] == []
    end

    test "search2 answers in the child form", context do
      result = call(context, "search2", %{"query" => "blue"})["searchResult2"]
      assert [%{"isDir" => true, "title" => "Kind of Blue"}] = result["album"]
    end
  end

  defp ids(context, type, params \\ %{}) do
    context |> list(Map.put(params, "type", type)) |> Enum.map(& &1["id"])
  end

  defp list(context, params) do
    call(context, "getAlbumList2", params)["albumList2"]["album"] || []
  end

  defp song_ids(context, endpoint, key, params) do
    (call(context, endpoint, params)[key]["song"] || []) |> Enum.map(& &1["id"])
  end

  defp search(context, query, params \\ %{}) do
    call(context, "search3", Map.put(params, "query", query))["searchResult3"]
  end

  defp call(context, endpoint, params) do
    body =
      context.conn
      |> get("/rest/#{endpoint}", Map.merge(params, %{"apiKey" => context.key, "f" => "json"}))
      |> json_response(200)
      |> Map.fetch!("subsonic-response")

    assert body["status"] == "ok", inspect(body["error"])
    body
  end

  defp error(context, endpoint, params) do
    body =
      context.conn
      |> get("/rest/#{endpoint}", Map.merge(params, %{"apiKey" => context.key, "f" => "json"}))
      |> json_response(200)
      |> Map.fetch!("subsonic-response")

    assert body["status"] == "failed"
    body["error"]["code"]
  end
end
