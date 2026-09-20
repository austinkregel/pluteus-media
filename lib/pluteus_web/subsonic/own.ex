defmodule PluteusWeb.Subsonic.Own do
  @moduledoc """
  The requesting principal's own data on the OpenSubsonic surface (spec-07
  §6.5, §6.6): stars, ratings, scrobbles, playlists, the play queue,
  bookmarks, and the principal itself.

  Every operation reads or writes only the requesting principal's data.
  Another principal's playlist answers error 70, as if it did not exist, and
  a playlist is never public: asking for one to be is error 50. What a client
  reports is recorded against its key's device, by identifier, and shown by
  the device's label.

  A song that is later recycled or purged stays where a playlist, queue or
  bookmark named it, and is left out of what is shown. The positions a client
  sees and sends back are positions among what it was shown.
  """

  alias Pluteus.Consumption
  alias Pluteus.Music
  alias Pluteus.Principals
  alias PluteusWeb.Subsonic.Request
  alias PluteusWeb.Subsonic.Response
  alias PluteusWeb.Subsonic.Shape

  @endpoints ~w(star unstar setRating scrobble getPlaylists getPlaylist createPlaylist
                updatePlaylist deletePlaylist getPlayQueue savePlayQueue getPlayQueueByIndex
                savePlayQueueByIndex getBookmarks createBookmark deleteBookmark getUser)

  @spec endpoints() :: [String.t()]
  def endpoints, do: @endpoints

  @spec handle(String.t(), Plug.Conn.t()) :: Plug.Conn.t()
  def handle(endpoint, conn) do
    case answer(endpoint, conn) do
      :ok -> Response.ok(conn, nil, %{})
      {:ok, key, body} -> Response.ok(conn, key, body)
      {:error, code, message} -> Response.error(conn, code, message)
    end
  end

  # --- Stars and ratings --------------------------------------------------------

  defp answer(endpoint, conn) when endpoint in ["star", "unstar"] do
    with {:ok, targets} <- star_targets(conn) do
      principal_id = principal_id(conn)

      Enum.each(targets, &mark(endpoint, principal_id, &1))
    end
  end

  defp answer("setRating", conn) do
    with {:ok, id} <- Request.required(conn, "id"),
         {:ok, rating} <- Request.integer(conn, "rating", nil, 0..5),
         {:ok, rating} <- present(rating, "rating"),
         {:ok, res_id} <- rateable(conn, id) do
      {:ok, _} = Consumption.rate(principal_id(conn), res_id, rating)
      :ok
    end
  end

  defp answer("scrobble", conn) do
    with {:ok, ids} <- Request.ids(conn, "id"),
         {:ok, ids} <- present(ids, "id"),
         {:ok, submission} <- Request.boolean(conn, "submission", true),
         {:ok, times} <- times(conn),
         {:ok, songs} <- songs(conn, ids) do
      device_id = conn.assigns.device.id

      songs
      |> Enum.with_index()
      |> Enum.each(fn {song, index} ->
        record_play(
          conn,
          device_id,
          submission,
          song,
          Enum.at(times, index) || DateTime.utc_now()
        )
      end)

      :ok
    end
  end

  # --- Playlists (§6.6) ---------------------------------------------------------

  defp answer("getPlaylists", conn) do
    with :ok <- own_username(conn) do
      playlists = Consumption.playlists(principal_id(conn))
      songs = visible_songs(conn, Enum.flat_map(playlists, & &1.entries))

      {:ok, "playlists", %{"playlist" => Enum.map(playlists, &playlist(conn, &1, songs, false))}}
    end
  end

  defp answer("getPlaylist", conn) do
    with {:ok, playlist} <- own_playlist(conn, "id") do
      songs = visible_songs(conn, playlist.entries)
      {:ok, "playlist", playlist(conn, playlist, songs, true)}
    end
  end

  defp answer("createPlaylist", conn) do
    with {:ok, song_ids} <- Request.ids(conn, "songId"),
         {:ok, songs} <- songs(conn, song_ids) do
      ids = Enum.map(songs, & &1.id)

      result = write_playlist(conn, Request.optional(conn, "playlistId"), ids)

      with {:ok, playlist} <- result do
        {:ok, "playlist", playlist(conn, playlist, visible_songs(conn, playlist.entries), true)}
      end
    end
  end

  defp answer("updatePlaylist", conn) do
    with {:ok, playlist} <- own_playlist(conn, "playlistId"),
         {:ok, public} <- Request.boolean(conn, "public", false),
         :ok <- private(public),
         {:ok, append} <- Request.ids(conn, "songIdToAdd"),
         {:ok, appended} <- songs(conn, append),
         {:ok, remove} <- indexes(conn, "songIndexToRemove") do
      shown = shown_positions(conn, playlist.entries)

      changes =
        %{
          append: Enum.map(appended, & &1.id),
          remove: for(index <- remove, position = Enum.at(shown, index), position, do: position)
        }
        |> put_present(:name, Request.optional(conn, "name"))
        |> put_present(:comment, Request.optional(conn, "comment"))

      {:ok, _} = Consumption.update_playlist(principal_id(conn), playlist.id, changes)
      :ok
    end
  end

  defp answer("deletePlaylist", conn) do
    with {:ok, playlist} <- own_playlist(conn, "id") do
      :ok = Consumption.delete_playlist(principal_id(conn), playlist.id)
    end
  end

  # --- The play queue -----------------------------------------------------------

  defp answer("getPlayQueue", conn) do
    {:ok, "playQueue",
     queue(conn, fn visible_index, songs -> current_id(visible_index, songs) end)}
  end

  defp answer("getPlayQueueByIndex", conn) do
    {:ok, "playQueueByIndex",
     queue(conn, fn visible_index, _songs -> {"currentIndex", visible_index} end)}
  end

  defp answer("savePlayQueue", conn) do
    with {:ok, ids} <- Request.ids(conn, "id"),
         {:ok, songs} <- songs(conn, ids),
         {:ok, position} <- Request.integer(conn, "position", 0, 0..9_223_372_036_854_775_807),
         {:ok, current} <- current_index(conn, Enum.map(songs, & &1.id)) do
      save_queue(conn, songs, current, position)
    end
  end

  defp answer("savePlayQueueByIndex", conn) do
    with {:ok, ids} <- Request.ids(conn, "id"),
         {:ok, songs} <- songs(conn, ids),
         {:ok, position} <- Request.integer(conn, "position", 0, 0..9_223_372_036_854_775_807),
         {:ok, current} <-
           Request.integer(conn, "currentIndex", nil, 0..max(length(songs) - 1, 0)) do
      save_queue(conn, songs, current, position)
    end
  end

  # --- Bookmarks ----------------------------------------------------------------

  defp answer("getBookmarks", conn) do
    bookmarks = Consumption.bookmarks(principal_id(conn))

    songs =
      Map.new(Music.songs(Enum.map(bookmarks, & &1.res_id), Request.profile(conn)), &{&1.id, &1})

    albums = albums_of(conn, Map.values(songs))
    context = Shape.context(conn, Map.keys(songs))

    {:ok, "bookmarks",
     %{
       "bookmark" =>
         for bookmark <- bookmarks, song = songs[bookmark.res_id], song do
           %{
             "position" => bookmark.position_ms,
             "username" => principal_id(conn),
             "comment" => bookmark.comment,
             "created" => Shape.timestamp(bookmark.inserted_at),
             "changed" => Shape.timestamp(bookmark.updated_at),
             "entry" => Shape.song(song, albums[song.album_id], context)
           }
         end
     }}
  end

  defp answer("createBookmark", conn) do
    with {:ok, id} <- Request.id(conn, "id"),
         {:ok, position} <- Request.integer(conn, "position", nil, 0..9_223_372_036_854_775_807),
         {:ok, position} <- present(position, "position"),
         {:ok, [song]} <- songs(conn, [id]) do
      {:ok, _} =
        Consumption.bookmark(
          principal_id(conn),
          song.id,
          position,
          Request.optional(conn, "comment")
        )

      :ok
    end
  end

  defp answer("deleteBookmark", conn) do
    with {:ok, id} <- Request.id(conn, "id") do
      case Consumption.delete_bookmark(principal_id(conn), id) do
        :ok -> :ok
        {:error, :not_found} -> Request.not_found(id)
      end
    end
  end

  # --- The principal ------------------------------------------------------------

  defp answer("getUser", conn) do
    with {:ok, username} <- Request.required(conn, "username"),
         :ok <- own(conn, username) do
      principal = conn.assigns.principal

      {:ok, "user",
       %{
         "username" => principal.id,
         "scrobblingEnabled" => true,
         "adminRole" => principal.role == "administrator",
         "settingsRole" => false,
         "downloadRole" => true,
         "uploadRole" => false,
         "playlistRole" => true,
         "coverArtRole" => false,
         "commentRole" => false,
         "podcastRole" => false,
         "streamRole" => true,
         "jukeboxRole" => false,
         "shareRole" => false,
         "videoConversionRole" => false,
         "folder" => [1]
       }}
    end
  end

  defp mark("star", principal_id, res_id), do: {:ok, _} = Consumption.star(principal_id, res_id)
  defp mark("unstar", principal_id, res_id), do: :ok = Consumption.unstar(principal_id, res_id)

  # A submission is a play; without one, the song is what the client plays now.
  defp record_play(conn, device_id, true, song, at),
    do: {:ok, _} = Consumption.played(principal_id(conn), device_id, song.id, at)

  defp record_play(conn, device_id, false, song, at),
    do: :ok = Consumption.playing(principal_id(conn), device_id, song.id, at)

  # With a playlistId, createPlaylist replaces that playlist's songs.
  defp write_playlist(conn, nil, ids) do
    with {:ok, name} <- Request.required(conn, "name"),
         do: Consumption.create_playlist(principal_id(conn), name, ids)
  end

  defp write_playlist(conn, _playlist_id, ids) do
    with {:ok, playlist} <- own_playlist(conn, "playlistId"),
         do: Consumption.update_playlist(principal_id(conn), playlist.id, %{songs: ids})
  end

  # --- Stars' and ratings' targets ----------------------------------------------

  # `id` names a song or an album, `albumId` an album, `artistId` an artist.
  # Every one is checked before any is starred, so a request naming something
  # unknown changes nothing.
  defp star_targets(conn) do
    profile = Request.profile(conn)

    targets =
      Enum.map(Request.all(conn, "id"), &song_or_album(&1, profile)) ++
        Enum.map(Request.all(conn, "albumId"), &album(&1, profile)) ++
        Enum.map(Request.all(conn, "artistId"), &artist(&1, profile))

    case Enum.find(targets, &match?({:error, _, _}, &1)) do
      nil when targets == [] -> Request.missing("id")
      nil -> {:ok, Enum.map(targets, fn {:ok, id} -> id end)}
      error -> error
    end
  end

  defp rateable(conn, id) do
    profile = Request.profile(conn)

    case song_or_album(id, profile) do
      {:ok, res_id} -> {:ok, res_id}
      {:error, 70, _} -> artist(id, profile)
    end
  end

  defp song_or_album(id, profile) do
    with {:ok, uuid} <- Request.uuid(id) do
      cond do
        Music.album(uuid, profile) -> {:ok, uuid}
        Music.song(uuid, profile) -> {:ok, uuid}
        true -> Request.not_found(id)
      end
    end
  end

  defp album(id, profile) do
    with {:ok, uuid} <- Request.uuid(id) do
      if Music.album(uuid, profile), do: {:ok, uuid}, else: Request.not_found(id)
    end
  end

  # An artist known only by a credited name is no res, and a star or rating is
  # kept against a res.
  defp artist(id, profile) do
    case Music.parse_artist_id(id) do
      {:agent, agent_id} ->
        known =
          profile
          |> Music.library()
          |> Music.artists()
          |> Enum.any?(fn {artist, _} -> artist.agent_id == agent_id end)

        if known, do: {:ok, agent_id}, else: Request.not_found(id)

      {:name, _name} ->
        {:error, 0, "An artist known only by a credited name cannot be starred or rated"}

      :error ->
        Request.not_found(id)
    end
  end

  # --- Songs --------------------------------------------------------------------

  # Every identifier must name a live song, or nothing is done.
  defp songs(conn, ids) do
    found = Music.songs(ids, Request.profile(conn))
    by_id = Map.new(found, &{&1.id, &1})

    case Enum.find(ids, &(not Map.has_key?(by_id, &1))) do
      nil -> {:ok, Enum.map(ids, &by_id[&1])}
      missing -> Request.not_found(missing)
    end
  end

  defp visible_songs(conn, entries) do
    songs = Music.songs(entries |> Enum.map(& &1.res_id) |> Enum.uniq(), Request.profile(conn))
    Map.new(songs, &{&1.id, &1})
  end

  defp albums_of(conn, songs) do
    songs
    |> Enum.map(& &1.album_id)
    |> Enum.uniq()
    |> Music.albums(Request.profile(conn))
    |> Map.new(&{&1.id, &1})
  end

  # The full positions of the entries a client is shown, in order.
  defp shown_positions(conn, entries) do
    songs = visible_songs(conn, entries)
    for entry <- entries, Map.has_key?(songs, entry.res_id), do: entry.position
  end

  # --- Playlists ----------------------------------------------------------------

  defp own_playlist(conn, key) do
    with {:ok, id} <- Request.id(conn, key) do
      case Consumption.playlist(principal_id(conn), id) do
        nil -> Request.not_found(id)
        playlist -> {:ok, playlist}
      end
    end
  end

  defp playlist(conn, playlist, songs, entries?) do
    shown = for entry <- playlist.entries, song = songs[entry.res_id], song, do: song

    base = %{
      "id" => playlist.id,
      "name" => playlist.name,
      "comment" => playlist.comment,
      "owner" => principal_id(conn),
      "public" => false,
      "songCount" => length(shown),
      "duration" => shown |> Enum.map(&(&1.duration_s || 0)) |> Enum.sum(),
      "created" => Shape.timestamp(playlist.inserted_at),
      "changed" => Shape.timestamp(playlist.updated_at)
    }

    if entries? do
      albums = albums_of(conn, shown)
      context = Shape.context(conn, Enum.map(shown, & &1.id))
      Map.put(base, "entry", Enum.map(shown, &Shape.song(&1, albums[&1.album_id], context)))
    else
      base
    end
  end

  defp private(true),
    do: {:error, 50, "A playlist is its principal's own and cannot be made public"}

  defp private(false), do: :ok

  # --- The play queue -----------------------------------------------------------

  defp queue(conn, current) do
    case Consumption.play_queue(principal_id(conn)) do
      nil ->
        %{"entry" => []}

      queue ->
        songs = visible_songs(conn, queue.entries)
        shown = for entry <- queue.entries, song = songs[entry.res_id], song, do: {entry, song}

        visible_index =
          Enum.find_index(shown, fn {entry, _} -> entry.position == queue.current_index end)

        albums = albums_of(conn, Enum.map(shown, &elem(&1, 1)))
        context = Shape.context(conn, Map.keys(songs))
        {key, value} = current.(visible_index, Enum.map(shown, &elem(&1, 1)))

        %{
          key => value,
          "position" => queue.position_ms,
          "username" => principal_id(conn),
          "changed" => Shape.timestamp(queue.updated_at),
          "changedBy" => device_label(conn, queue.changed_by_device_id),
          "entry" =>
            Enum.map(shown, fn {_entry, song} ->
              Shape.song(song, albums[song.album_id], context)
            end)
        }
    end
  end

  defp current_id(nil, _songs), do: {"current", nil}
  defp current_id(index, songs), do: {"current", Enum.at(songs, index).id}

  # `current` names a song; where it appears more than once, its first place.
  defp current_index(conn, ids) do
    case Request.optional(conn, "current") do
      nil ->
        {:ok, nil}

      current ->
        case Enum.find_index(ids, &(&1 == current)) do
          nil -> {:error, 0, "The current song #{current} is not in the queue"}
          index -> {:ok, index}
        end
    end
  end

  defp save_queue(conn, songs, current, position) do
    case Consumption.save_play_queue(
           principal_id(conn),
           Enum.map(songs, & &1.id),
           current,
           position,
           conn.assigns.device.id
         ) do
      {:ok, _queue} -> :ok
      {:error, :current_outside_queue} -> {:error, 0, "The current index is outside the queue"}
    end
  end

  # --- Parameters ---------------------------------------------------------------

  defp times(conn) do
    conn
    |> Request.all("time")
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      with {milliseconds, ""} <- Integer.parse(value),
           {:ok, at} <- DateTime.from_unix(milliseconds, :millisecond) do
        {:cont, {:ok, [at | acc]}}
      else
        _invalid -> {:halt, {:error, 0, "time must be milliseconds since the epoch"}}
      end
    end)
    |> case do
      {:ok, times} -> {:ok, Enum.reverse(times)}
      error -> error
    end
  end

  defp indexes(conn, key) do
    conn
    |> Request.all(key)
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case Integer.parse(value) do
        {index, ""} when index >= 0 -> {:cont, {:ok, [index | acc]}}
        _invalid -> {:halt, {:error, 0, "#{key} must be whole numbers"}}
      end
    end)
  end

  defp own_username(conn) do
    case Request.optional(conn, "username") do
      nil -> :ok
      username -> own(conn, username)
    end
  end

  defp own(conn, username) do
    if username == principal_id(conn),
      do: :ok,
      else: {:error, 50, "Only the requesting principal's own data is served"}
  end

  defp present(nil, key), do: Request.missing(key)
  defp present([], key), do: Request.missing(key)
  defp present(value, _key), do: {:ok, value}

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp principal_id(conn), do: conn.assigns.principal.id

  defp device_label(conn, device_id) do
    conn
    |> principal_id()
    |> Principals.devices_of()
    |> Enum.find(&(&1.id == device_id))
    |> Map.fetch!(:label)
  end
end
