defmodule PluteusWeb.SubsonicBrowseTest do
  @moduledoc """
  Browsing on the OpenSubsonic surface: spec-07 §6.3, §6.4 and criteria 17
  and 21.
  """

  use PluteusWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Actor
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Credit
  alias Pluteus.Ingest.Place
  alias Pluteus.Lifecycle
  alias Pluteus.Music
  alias Pluteus.MusicFixtures
  alias Pluteus.Principals
  alias Pluteus.Principals.Principal
  alias Pluteus.Repo

  @subject "ada@example.test"

  setup %{conn: conn} do
    library = MusicFixtures.library!()

    %{"key" => key} =
      conn
      |> through_proxy(@subject)
      |> post("/devices", %{"label" => "phone"})
      |> json_response(201)

    %{
      conn: via_proxy(conn),
      key: key,
      library: library,
      album: library.albums["01 So What.flac"],
      so_what: library.songs["01 So What.flac"],
      freddie: library.songs["02 Freddie.flac"]
    }
  end

  describe "17. An album is a release, a song a track, an artist a credit's agent or name" do
    test "the album holds its tracks in order, credited by name", context do
      album = call(context, "getAlbum", %{"id" => context.album})["album"]

      assert album["name"] == "Kind of Blue"
      assert album["songCount"] == 2
      assert album["artist"] == "Miles Davis"
      assert album["artistId"] == Music.name_artist_id("Miles Davis")
      assert album["year"] == 1959

      assert Enum.map(album["song"], &{&1["id"], &1["title"], &1["track"], &1["discNumber"]}) ==
               [{context.so_what, "So What", 1, 1}, {context.freddie, "Freddie Freeloader", 2, 1}]

      [so_what, _] = album["song"]
      assert so_what["albumId"] == context.album
      assert so_what["genre"] == "Modal"
      assert so_what["contentType"] == "audio/flac"
      assert so_what["suffix"] == "flac"
      assert is_integer(so_what["duration"])
      refute Map.has_key?(so_what, "path")
    end

    test "a credit resolved to an agent is that agent, under the agent's name", context do
      {:ok, %{res: agent}} =
        Actor.as(Principals.system!().id, fn ->
          Catalog.create_named_res(:person, "Miles Dewey Davis III")
        end)

      {_count, _} =
        Repo.update_all(Credit, set: [agent_id: agent.id, agent_kind: :person])

      album = call(context, "getAlbum", %{"id" => context.album})["album"]

      assert album["artistId"] == agent.id
      assert album["artist"] == "Miles Dewey Davis III"
    end

    test "a member's credit outranks placement's in the same role", context do
      {:ok, _} =
        %Credit{}
        |> Credit.changeset(%{
          work_id: work_of(context.album),
          role: :album_artist,
          position: 1,
          name: "Davis Sextet",
          provenance: :local
        })
        |> Repo.insert()

      album = call(context, "getAlbum", %{"id" => context.album})["album"]
      assert album["artist"] == "Davis Sextet"
      assert [%{"name" => "Miles Davis"}] = hd(album["song"])["artists"]
    end

    test "an album credited to nobody is credited to its songs' artists", context do
      {_count, _} =
        Repo.delete_all(
          from c in Credit,
            where: c.role == :album_artist and c.work_id == ^work_of(context.album)
        )

      {:ok, _} =
        %Credit{}
        |> Credit.changeset(%{
          work_id: work_of(context.freddie),
          role: :artist,
          position: 2,
          name: "Cannonball Adderley",
          provenance: :automatic
        })
        |> Repo.insert()

      album = call(context, "getAlbum", %{"id" => context.album})["album"]
      assert Enum.map(album["artists"], & &1["name"]) == ["Miles Davis", "Cannonball Adderley"]
    end

    test "every name is the one the principal's profile prefers", context do
      principal = Principals.principal_for(issuer(), @subject)
      {:ok, %{res: person}} = Catalog.create_named_res(:person, "Ada")

      {:ok, _} =
        principal
        |> Principal.changeset(%{person_id: person.id, person_kind: :person})
        |> Repo.update()

      {:ok, _} =
        Catalog.create_nomen(%{
          res_id: context.album,
          nomen_string: "the blue one",
          assigner_id: person.id
        })

      assert call(context, "getAlbum", %{"id" => context.album})["album"]["name"] ==
               "the blue one"
    end

    test "artists are listed by initial, and an artist lists its albums", context do
      artists = call(context, "getArtists", %{})["artists"]["index"]
      id = Music.name_artist_id("Miles Davis")

      assert %{"name" => "M", "artist" => [%{"id" => ^id, "albumCount" => 1}]} =
               Enum.find(artists, &(&1["name"] == "M"))

      artist = call(context, "getArtist", %{"id" => id})["artist"]
      assert [%{"id" => album_id, "name" => "Kind of Blue"}] = artist["album"]
      assert album_id == context.album
    end

    test "the directories are artists, their albums, and the albums' songs", context do
      id = Music.name_artist_id("Miles Davis")

      artist = call(context, "getMusicDirectory", %{"id" => id})["directory"]
      assert [%{"id" => album_id, "isDir" => true}] = artist["child"]
      assert album_id == context.album

      album = call(context, "getMusicDirectory", %{"id" => album_id})["directory"]
      assert Enum.map(album["child"], & &1["id"]) == [context.so_what, context.freddie]
      assert Enum.all?(album["child"], &(&1["isDir"] == false))
    end

    test "a song, and the genres its probe names", context do
      song = call(context, "getSong", %{"id" => context.freddie})["song"]
      assert {song["title"], song["album"]} == {"Freddie Freeloader", "Kind of Blue"}

      genres = call(context, "getGenres", %{})["genres"]["genre"]
      assert %{"value" => "Jazz", "songCount" => 1, "albumCount" => 1} in genres
    end

    test "a track with no album evidence is an album of its own", context do
      loose = context.library.albums["untitled.wav"]
      album = call(context, "getAlbum", %{"id" => loose})["album"]

      assert album["songCount"] == 1
      refute Map.has_key?(album, "artist")
    end
  end

  describe "album and artist info" do
    test "an album's notes are its description, with its MusicBrainz release", context do
      info = call(context, "getAlbumInfo2", %{"id" => context.album})["albumInfo"]

      assert info == %{
               "notes" => "Recorded at Columbia 30th Street Studio.",
               "musicBrainzId" => context.library.release
             }
    end

    test "an album the catalog knows nothing more of has empty info", context do
      loose = context.library.albums["untitled.wav"]
      assert call(context, "getAlbumInfo2", %{"id" => loose})["albumInfo"] == %{}
    end
  end

  describe "cover art and lyrics" do
    test "an album's cover is its cover companion, as stored", context do
      response = raw(context, "getCoverArt", %{"id" => context.album})

      assert response.status == 200
      assert response.resp_body == context.library.cover
      assert get_resp_header(response, "content-type") == ["image/png"]
    end

    test "a song with no companion of its own falls to its album's", context do
      response = raw(context, "getCoverArt", %{"id" => context.so_what})
      assert response.resp_body == context.library.cover
    end

    test "with no companion, the picture embedded in the track", context do
      {:ok, _} =
        Lifecycle.recycle(
          Catalog.associated(context.album, Place.companion_link("cover_art"))
          |> hd(),
          Principals.system!().id
        )

      response = raw(context, "getCoverArt", %{"id" => context.album})

      assert response.status == 200
      assert get_resp_header(response, "content-type") == ["image/jpeg"]
      assert <<0xFF, 0xD8, _rest::binary>> = response.resp_body
    end

    test "lyrics are the song's LRC companion, synchronized", context do
      [lyrics] =
        call(context, "getLyricsBySongId", %{"id" => context.so_what})["lyricsList"][
          "structuredLyrics"
        ]

      assert lyrics["synced"] == true

      assert lyrics["line"] == [
               %{"start" => 500, "value" => "Count in"},
               %{"start" => 1_500, "value" => "First line"},
               %{"start" => 3_250, "value" => "Twice sung"},
               %{"start" => 7_000, "value" => "Twice sung"}
             ]

      assert call(context, "getLyricsBySongId", %{"id" => context.freddie})["lyricsList"] ==
               %{"structuredLyrics" => []}
    end
  end

  describe "21. A recycled or purged entity answers error 70" do
    test "a recycled album and song are not found, and leave the lists", context do
      principal = Principals.system!()
      {:ok, _} = Lifecycle.recycle(context.freddie, principal.id)

      assert error(context, "getSong", %{"id" => context.freddie}) == 70
      album = call(context, "getAlbum", %{"id" => context.album})["album"]
      assert Enum.map(album["song"], & &1["id"]) == [context.so_what]

      {:ok, _} = Lifecycle.recycle(context.album, principal.id)
      assert error(context, "getAlbum", %{"id" => context.album}) == 70
      assert error(context, "getCoverArt", %{"id" => context.album}) == 70
    end

    test "an identifier naming nothing, or not an identifier, is error 70", context do
      assert error(context, "getAlbum", %{"id" => UUIDv7.generate()}) == 70
      assert error(context, "getAlbum", %{"id" => "nope"}) == 70
      assert error(context, "getArtist", %{"id" => Music.name_artist_id("Nobody")}) == 70
      assert error(context, "getAlbum", %{}) == 10
    end
  end

  test "XML is the default, with the same content", context do
    response = raw(context, "getAlbum", %{"id" => context.album}, nil)

    assert get_resp_header(response, "content-type") == ["text/xml; charset=utf-8"]
    assert response.resp_body =~ ~s(<album )
    assert response.resp_body =~ ~s(name="Kind of Blue")
    assert response.resp_body =~ ~s(<song )
  end

  defp work_of(manifestation_id) do
    [expression | _] = Catalog.expressions_in(manifestation_id)
    expression.work_id
  end

  defp call(context, endpoint, params) do
    body =
      context
      |> raw(endpoint, params)
      |> json_response(200)
      |> Map.fetch!("subsonic-response")

    assert body["status"] == "ok", inspect(body["error"])
    body
  end

  defp error(context, endpoint, params) do
    body =
      context |> raw(endpoint, params) |> json_response(200) |> Map.fetch!("subsonic-response")

    assert body["status"] == "failed"
    body["error"]["code"]
  end

  defp raw(context, endpoint, params, format \\ "json") do
    params = Map.put(params, "apiKey", context.key)
    params = if format, do: Map.put(params, "f", format), else: params
    get(context.conn, "/rest/#{endpoint}", params)
  end
end
