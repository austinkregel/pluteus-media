defmodule PluteusWeb.Subsonic.Lists do
  @moduledoc """
  The list and search endpoints of spec-07 §6.3.

  Every list that orders by consumption — `highest`, `frequent`, `recent`,
  `starred`, `getStarred`, `getNowPlaying` — reads only the requesting
  principal's own stars, ratings, plays and sessions (§6.5). No list is
  ordered or counted by anyone else's.

  Search matches every name a res carries, not only the one it is shown
  under (spec-01 §7.4); an empty query, as clients send to list everything,
  matches all.
  """

  alias Pluteus.Consumption
  alias Pluteus.Events
  alias Pluteus.Music
  alias Pluteus.Music.Album
  alias Pluteus.Principals
  alias PluteusWeb.Subsonic.Request
  alias PluteusWeb.Subsonic.Response
  alias PluteusWeb.Subsonic.Shape

  @folder "1"
  @played "played"

  @endpoints ~w(getAlbumList getAlbumList2 getRandomSongs getSongsByGenre getNowPlaying
                getStarred getStarred2 search2 search3)

  @spec endpoints() :: [String.t()]
  def endpoints, do: @endpoints

  @spec handle(String.t(), Plug.Conn.t()) :: Plug.Conn.t()
  def handle(endpoint, conn) do
    case answer(endpoint, conn) do
      {:ok, key, body} -> Response.ok(conn, key, body)
      {:error, code, message} -> Response.error(conn, code, message)
    end
  end

  # --- Album lists --------------------------------------------------------------

  defp answer(endpoint, conn) when endpoint in ["getAlbumList", "getAlbumList2"] do
    with {:ok, type} <- Request.required(conn, "type"),
         {:ok, size} <- Request.integer(conn, "size", 10, 0..500),
         {:ok, offset} <- Request.integer(conn, "offset", 0, 0..1_000_000),
         :ok <- folder(conn),
         {:ok, albums} <- album_list(type, conn) do
      shown = albums |> Enum.drop(offset) |> Enum.take(size)
      context = Shape.context(conn, Shape.ids(shown))

      case endpoint do
        "getAlbumList" ->
          {:ok, "albumList",
           %{"album" => Enum.map(shown, &Shape.album_child(&1, first_artist(&1), context))}}

        "getAlbumList2" ->
          {:ok, "albumList2", %{"album" => Enum.map(shown, &Shape.album(&1, context, false))}}
      end
    end
  end

  defp answer("getRandomSongs", conn) do
    with {:ok, size} <- Request.integer(conn, "size", 10, 0..500),
         {:ok, from_year} <- Request.integer(conn, "fromYear", nil, 0..9999),
         {:ok, to_year} <- Request.integer(conn, "toYear", nil, 0..9999),
         :ok <- folder(conn) do
      genre = Request.optional(conn, "genre")

      songs =
        conn
        |> library()
        |> pairs()
        |> Enum.filter(fn {song, _album} ->
          (is_nil(genre) or genre in Music.genres(song)) and
            within?(Music.year(song), from_year, to_year)
        end)
        |> Enum.shuffle()
        |> Enum.take(size)

      {:ok, "randomSongs", %{"song" => shape_songs(conn, songs)}}
    end
  end

  defp answer("getSongsByGenre", conn) do
    with {:ok, genre} <- Request.required(conn, "genre"),
         {:ok, count} <- Request.integer(conn, "count", 10, 0..500),
         {:ok, offset} <- Request.integer(conn, "offset", 0, 0..1_000_000),
         :ok <- folder(conn) do
      songs =
        conn
        |> library()
        |> pairs()
        |> Enum.filter(fn {song, _album} -> genre in Music.genres(song) end)
        |> Enum.drop(offset)
        |> Enum.take(count)

      {:ok, "songsByGenre", %{"song" => shape_songs(conn, songs)}}
    end
  end

  defp answer("getNowPlaying", conn) do
    principal_id = conn.assigns.principal.id
    playing = Consumption.now_playing(principal_id)

    songs =
      Map.new(Music.songs(Enum.map(playing, & &1.res_id), Request.profile(conn)), &{&1.id, &1})

    albums = albums_by_id(conn, Map.values(songs))
    context = Shape.context(conn, Map.keys(songs))
    labels = Map.new(Principals.devices_of(principal_id), &{&1.id, &1.label})
    now = DateTime.utc_now()

    entries =
      for session <- playing, song = songs[session.res_id], song do
        song
        |> Shape.song(albums[song.album_id], context)
        |> Map.merge(%{
          "username" => principal_id,
          "minutesAgo" => div(DateTime.diff(now, session.started_at), 60),
          "playerId" => session.device_id,
          "playerName" => labels[session.device_id]
        })
      end

    {:ok, "nowPlaying", %{"entry" => entries}}
  end

  defp answer(endpoint, conn) when endpoint in ["getStarred", "getStarred2"] do
    starred = Enum.map(Consumption.starred(conn.assigns.principal.id), & &1.res_id)
    library = library(conn)
    context = Shape.context(conn, Shape.ids(library))
    albums = Map.new(library, &{&1.id, &1})
    songs = Map.new(pairs(library), fn {song, album} -> {song.id, {song, album}} end)

    artists =
      Map.new(Music.artists(library), fn {artist, list} -> {artist.id, {artist, list}} end)

    starred_albums = for id <- starred, album = albums[id], album, do: album
    starred_songs = for id <- starred, pair = songs[id], pair, do: pair
    starred_artists = for id <- starred, entry = artists[id], entry, do: entry

    body = %{
      "artist" =>
        Enum.map(starred_artists, fn {artist, list} -> Shape.artist(artist, list, context) end),
      "song" => Enum.map(starred_songs, fn {song, album} -> Shape.song(song, album, context) end)
    }

    case endpoint do
      "getStarred" ->
        {:ok, "starred",
         Map.put(
           body,
           "album",
           Enum.map(starred_albums, &Shape.album_child(&1, first_artist(&1), context))
         )}

      "getStarred2" ->
        {:ok, "starred2",
         Map.put(body, "album", Enum.map(starred_albums, &Shape.album(&1, context, false)))}
    end
  end

  # --- Search -------------------------------------------------------------------

  defp answer(endpoint, conn) when endpoint in ["search2", "search3"] do
    with {:ok, artist_count} <- Request.integer(conn, "artistCount", 20, 0..500),
         {:ok, artist_offset} <- Request.integer(conn, "artistOffset", 0, 0..1_000_000),
         {:ok, album_count} <- Request.integer(conn, "albumCount", 20, 0..500),
         {:ok, album_offset} <- Request.integer(conn, "albumOffset", 0, 0..1_000_000),
         {:ok, song_count} <- Request.integer(conn, "songCount", 20, 0..500),
         {:ok, song_offset} <- Request.integer(conn, "songOffset", 0, 0..1_000_000),
         :ok <- folder(conn) do
      query =
        conn |> Request.optional("query") |> Kernel.||("") |> String.trim("\"") |> String.trim()

      library = library(conn)
      all_pairs = pairs(library)
      all_artists = Music.artists(library)

      {albums, songs, artists} = matching(library, all_pairs, all_artists, query)

      albums = albums |> Enum.drop(album_offset) |> Enum.take(album_count)
      songs = songs |> Enum.drop(song_offset) |> Enum.take(song_count)
      artists = artists |> Enum.drop(artist_offset) |> Enum.take(artist_count)
      context = Shape.context(conn, Shape.ids(library))

      body = %{
        "artist" =>
          Enum.map(artists, fn {artist, list} -> Shape.artist(artist, list, context) end),
        "song" => Enum.map(songs, fn {song, album} -> Shape.song(song, album, context) end)
      }

      case endpoint do
        "search2" ->
          {:ok, "searchResult2",
           Map.put(
             body,
             "album",
             Enum.map(albums, &Shape.album_child(&1, first_artist(&1), context))
           )}

        "search3" ->
          {:ok, "searchResult3",
           Map.put(body, "album", Enum.map(albums, &Shape.album(&1, context, false)))}
      end
    end
  end

  defp matching(library, pairs, artists, ""), do: {library, pairs, artists}

  defp matching(library, pairs, artists, query) do
    named =
      Music.named_containing(
        Enum.map(library, & &1.id) ++
          Enum.map(pairs, &elem(&1, 0).id) ++
          for({artist, _} <- artists, artist.agent_id, do: artist.agent_id),
        query
      )

    {Enum.filter(library, &(&1.id in named)),
     Enum.filter(pairs, fn {song, _} -> song.id in named end),
     Enum.filter(artists, fn {artist, _} -> artist_matches?(artist, named, query) end)}
  end

  defp artist_matches?(%{agent_id: nil, name: name}, _named, query),
    do: String.contains?(String.downcase(name), String.downcase(query))

  defp artist_matches?(%{agent_id: agent_id}, named, _query), do: agent_id in named

  # --- The album lists' orders --------------------------------------------------

  defp album_list("random", conn), do: {:ok, conn |> library() |> Enum.shuffle()}

  defp album_list("newest", conn),
    do:
      {:ok,
       conn
       |> library()
       |> Enum.sort_by(&{DateTime.to_unix(&1.created, :microsecond), &1.id}, :desc)}

  defp album_list("alphabeticalByName", conn),
    do: {:ok, conn |> library() |> Enum.sort_by(&{String.downcase(&1.name), &1.id})}

  defp album_list("alphabeticalByArtist", conn) do
    {:ok,
     conn
     |> library()
     |> Enum.sort_by(&{String.downcase(artist_name(&1)), String.downcase(&1.name), &1.id})}
  end

  defp album_list("starred", conn) do
    library = Map.new(library(conn), &{&1.id, &1})

    starred =
      for star <- Consumption.starred(conn.assigns.principal.id),
          album = library[star.res_id],
          album,
          do: album

    {:ok, starred}
  end

  defp album_list("highest", conn) do
    library = library(conn)
    ratings = Consumption.ratings(conn.assigns.principal.id, Enum.map(library, & &1.id))

    {:ok,
     library
     |> Enum.filter(&Map.has_key?(ratings, &1.id))
     |> Enum.sort_by(&{-ratings[&1.id], &1.id})}
  end

  defp album_list("frequent", conn) do
    {:ok, plays_by_album(conn, fn plays -> {-length(plays), nil} end)}
  end

  defp album_list("recent", conn) do
    {:ok,
     plays_by_album(conn, fn plays ->
       {-(plays |> Enum.map(&DateTime.to_unix(&1, :microsecond)) |> Enum.max()), nil}
     end)}
  end

  defp album_list("byYear", conn) do
    with {:ok, from_year} <- required_integer(conn, "fromYear"),
         {:ok, to_year} <- required_integer(conn, "toYear") do
      albums =
        conn
        |> library()
        |> Enum.filter(&within?(album_year(&1), min(from_year, to_year), max(from_year, to_year)))
        |> Enum.sort_by(&{album_year(&1), &1.id})

      {:ok, if(from_year > to_year, do: Enum.reverse(albums), else: albums)}
    end
  end

  defp album_list("byGenre", conn) do
    with {:ok, genre} <- Request.required(conn, "genre") do
      {:ok,
       conn
       |> library()
       |> Enum.filter(fn album -> Enum.any?(album.songs, &(genre in Music.genres(&1))) end)}
    end
  end

  defp album_list(type, _conn), do: {:error, 0, "Unknown album list type: #{type}"}

  # The principal's own plays of each album's songs, ordered by `rank` over
  # the times each album was played. An album never played is not listed.
  defp plays_by_album(conn, rank) do
    library = library(conn)
    album_of = for album <- library, song <- album.songs, into: %{}, do: {song.id, album}

    conn.assigns.principal.id
    |> Events.for_principal()
    |> Enum.filter(&(&1.type == @played and Map.has_key?(album_of, &1.res_id)))
    |> Enum.group_by(&album_of[&1.res_id].id, & &1.occurred_at)
    |> Enum.map(fn {album_id, plays} -> {album_id, put_elem(rank.(plays), 1, album_id)} end)
    |> Enum.sort_by(&elem(&1, 1))
    |> Enum.map(fn {album_id, _rank} -> Enum.find(library, &(&1.id == album_id)) end)
  end

  # --- Common -------------------------------------------------------------------

  defp library(conn), do: Music.library(Request.profile(conn))

  defp pairs(library), do: for(album <- library, song <- album.songs, do: {song, album})

  defp albums_by_id(conn, songs) do
    songs
    |> Enum.map(& &1.album_id)
    |> Enum.uniq()
    |> Music.albums(Request.profile(conn))
    |> Map.new(&{&1.id, &1})
  end

  defp shape_songs(conn, pairs) do
    context = Shape.context(conn, Enum.map(pairs, &elem(&1, 0).id))
    Enum.map(pairs, fn {song, album} -> Shape.song(song, album, context) end)
  end

  defp folder(conn) do
    case Request.optional(conn, "musicFolderId") do
      nil -> :ok
      @folder -> :ok
      other -> Request.not_found(other)
    end
  end

  defp required_integer(conn, key) do
    case Request.integer(conn, key, nil, 0..9999) do
      {:ok, nil} -> Request.missing(key)
      other -> other
    end
  end

  defp within?(_year, nil, nil), do: true
  defp within?(nil, _from, _to), do: false
  defp within?(year, from, to), do: (is_nil(from) or year >= from) and (is_nil(to) or year <= to)

  defp album_year(%Album{songs: [first | _]}), do: Music.year(first)
  defp album_year(%Album{songs: []}), do: nil

  defp artist_name(%Album{artists: []}), do: ""
  defp artist_name(%Album{artists: artists}), do: Enum.map_join(artists, ", ", & &1.name)

  defp first_artist(%Album{artists: []}), do: nil
  defp first_artist(%Album{artists: [artist | _]}), do: artist.id
end
