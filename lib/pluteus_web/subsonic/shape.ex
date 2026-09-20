defmodule PluteusWeb.Subsonic.Shape do
  @moduledoc """
  Albums, songs and artists as the Subsonic protocol represents them, with the
  requesting principal's own stars and ratings on each (spec-07 §6.4, §6.5).

  Every identifier is the res's own. A song's and an album's cover art is
  asked for by the song's or album's identifier, and no path is given: storage
  has no directories that mean anything (spec-04 §4.5).
  """

  alias Pluteus.Consumption
  alias Pluteus.Events
  alias Pluteus.Ingest.Registry
  alias Pluteus.Music
  alias Pluteus.Music.Album
  alias Pluteus.Music.Artist
  alias Pluteus.Music.Song

  @type context :: %{starred: map(), ratings: map(), plays: map(), bookmarks: map()}

  @doc """
  The principal's own stars, ratings, plays and bookmarks over the res a
  response shows. A song carries what its own principal did with it and
  nothing of anyone else's (spec-07 §6.5).
  """
  @spec context(Plug.Conn.t(), [Ecto.UUID.t()]) :: context()
  def context(conn, res_ids) do
    principal_id = conn.assigns.principal.id

    %{
      starred: Consumption.starred_at(principal_id, res_ids),
      ratings: Consumption.ratings(principal_id, res_ids),
      plays: Events.plays(principal_id, res_ids, "played"),
      bookmarks:
        principal_id
        |> Consumption.bookmarks()
        |> Map.new(&{&1.res_id, &1.position_ms})
    }
  end

  @doc """
  Every res identifier the albums show, songs and artists included.
  """
  @spec ids([Album.t()]) :: [Ecto.UUID.t()]
  def ids(albums) do
    Enum.flat_map(albums, fn album ->
      [album.id | Enum.map(album.songs, & &1.id)] ++
        Enum.map(album.artists, & &1.id) ++
        for(song <- album.songs, artist <- song.artists, do: artist.id)
    end)
  end

  @spec song(Song.t(), Album.t(), context()) :: map()
  def song(%Song{} = song, %Album{} = album, context) do
    genres = Music.genres(song)
    stream = Music.audio_stream(song)
    {play_count, last_played} = Map.get(context.plays, song.id, {0, nil})

    %{
      "id" => song.id,
      "parent" => album.id,
      "isDir" => false,
      "title" => song.title,
      "album" => album.name,
      "albumId" => album.id,
      "artist" => display(song.artists),
      "artistId" => first_id(song.artists),
      "artists" => Enum.map(song.artists, &artist_ref/1),
      "displayArtist" => display(song.artists),
      "albumArtists" => Enum.map(album.artists, &artist_ref/1),
      "displayAlbumArtist" => display(album.artists),
      "track" => song.track,
      "discNumber" => song.disc,
      "year" => Music.year(song),
      "genre" => List.first(genres),
      "genres" => Enum.map(genres, &%{"name" => &1}),
      "coverArt" => song.id,
      "size" => song.master && song.master.size,
      "contentType" => song.master && Registry.media_type(song.master.format),
      "suffix" => song.suffix,
      "duration" => song.duration_s,
      "bitRate" => Music.bit_rate(song),
      "created" => timestamp(song.created),
      "type" => "music",
      "mediaType" => "song",
      "isVideo" => false,
      "bitDepth" => bit_depth(stream),
      "samplingRate" => integer(stream["sample_rate"]),
      "channelCount" => stream["channels"],
      "bpm" => song.bpm && round(song.bpm),
      "comment" => Music.tag(song, ["comment", "description"]),
      "musicBrainzId" => Music.tag(song, ["musicbrainz_trackid", "musicbrainz_releasetrackid"]),
      "starred" => timestamp(context.starred[song.id]),
      "userRating" => context.ratings[song.id],
      "playCount" => play_count,
      "played" => timestamp(last_played),
      "bookmarkPosition" => bookmark_seconds(context.bookmarks[song.id])
    }
  end

  # A lossy codec has no bit depth, and the protocol asks for the field all the
  # same; zero is the value it reads as "none", as it is for a bit rate.
  defp bit_depth(stream) do
    integer(stream["bits_per_raw_sample"]) || integer(stream["bits_per_sample"]) || 0
  end

  defp integer(nil), do: nil
  defp integer(value) when is_integer(value), do: if(value == 0, do: nil, else: value)

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _other -> nil
    end
  end

  defp bookmark_seconds(nil), do: nil
  defp bookmark_seconds(position_ms), do: div(position_ms, 1000)

  @doc """
  An album as an ID3 album, with its songs where `songs?`.
  """
  @spec album(Album.t(), context(), boolean()) :: map()
  def album(%Album{} = album, context, songs?) do
    first = List.first(album.songs)

    base = %{
      "id" => album.id,
      "name" => album.name,
      "artist" => display(album.artists),
      "artistId" => first_id(album.artists),
      "artists" => Enum.map(album.artists, &artist_ref/1),
      "displayArtist" => display(album.artists),
      "coverArt" => album.id,
      "songCount" => length(album.songs),
      "duration" => album.songs |> Enum.map(&(&1.duration_s || 0)) |> Enum.sum(),
      "created" => timestamp(album.created),
      "year" => first && Music.year(first),
      "genre" => first && List.first(Music.genres(first)),
      "genres" => album_genres(album),
      "starred" => timestamp(context.starred[album.id]),
      "userRating" => context.ratings[album.id]
    }

    if songs?,
      do: Map.put(base, "song", Enum.map(album.songs, &song(&1, album, context))),
      else: base
  end

  @doc """
  An album as a directory entry under its artist.
  """
  @spec album_child(Album.t(), String.t() | nil, context()) :: map()
  def album_child(%Album{} = album, parent, context) do
    album
    |> album(context, false)
    |> Map.merge(%{
      "parent" => parent,
      "isDir" => true,
      "title" => album.name,
      "album" => album.name
    })
  end

  @spec artist(Artist.t(), [Album.t()], context()) :: map()
  def artist(%Artist{} = artist, albums, context) do
    %{
      "id" => artist.id,
      "name" => artist.name,
      "albumCount" => length(albums),
      "coverArt" => albums |> List.first() |> then(&(&1 && &1.id)),
      "musicBrainzId" => artist.musicbrainz_id,
      "starred" => timestamp(context.starred[artist.id])
    }
  end

  @doc """
  Artists grouped under the first letter of their names, as `getArtists` and
  `getIndexes` give them.
  """
  @spec index([{Artist.t(), [Album.t()]}], (Artist.t(), [Album.t()] -> map())) :: [map()]
  def index(artists, shape) do
    artists
    |> Enum.group_by(fn {artist, _albums} -> letter(artist.name) end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {letter, members} ->
      %{"name" => letter, "artist" => Enum.map(members, fn {a, albums} -> shape.(a, albums) end)}
    end)
  end

  defp letter(name) do
    first = name |> String.normalize(:nfd) |> String.first() |> String.upcase()
    if first =~ ~r/\A\p{L}\z/u, do: first, else: "#"
  end

  defp album_genres(album) do
    album.songs
    |> Enum.flat_map(&Music.genres/1)
    |> Enum.uniq()
    |> Enum.map(&%{"name" => &1})
  end

  defp artist_ref(%Artist{} = artist), do: %{"id" => artist.id, "name" => artist.name}

  defp display([]), do: nil
  defp display(artists), do: Enum.map_join(artists, ", ", & &1.name)

  defp first_id([]), do: nil
  defp first_id([artist | _]), do: artist.id

  @spec timestamp(DateTime.t() | nil) :: String.t() | nil
  def timestamp(nil), do: nil
  def timestamp(%DateTime{} = at), do: at |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
