defmodule PluteusWeb.Subsonic.Shape do
  @moduledoc """
  Albums, songs and artists as the Subsonic protocol represents them, with the
  requesting principal's own stars and ratings on each (spec-07 §6.4, §6.5).

  Every identifier is the res's own. A song's and an album's cover art is
  asked for by the song's or album's identifier, and no path is given: storage
  has no directories that mean anything (spec-04 §4.5).
  """

  alias Pluteus.Consumption
  alias Pluteus.Ingest.Registry
  alias Pluteus.Music
  alias Pluteus.Music.Album
  alias Pluteus.Music.Artist
  alias Pluteus.Music.Song

  @type context :: %{starred: map(), ratings: map()}

  @doc """
  The principal's own stars and ratings over the res a response shows.
  """
  @spec context(Plug.Conn.t(), [Ecto.UUID.t()]) :: context()
  def context(conn, res_ids) do
    principal_id = conn.assigns.principal.id

    %{
      starred: Consumption.starred_at(principal_id, res_ids),
      ratings: Consumption.ratings(principal_id, res_ids)
    }
  end

  @doc """
  Every res identifier the albums show, songs and resolved artists included.
  """
  @spec ids([Album.t()]) :: [Ecto.UUID.t()]
  def ids(albums) do
    Enum.flat_map(albums, fn album ->
      [album.id | Enum.map(album.songs, & &1.id)] ++
        for(artist <- album.artists, artist.agent_id, do: artist.agent_id)
    end)
  end

  @spec song(Song.t(), Album.t(), context()) :: map()
  def song(%Song{} = song, %Album{} = album, context) do
    genres = Music.genres(song)

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
      "starred" => timestamp(context.starred[song.id]),
      "userRating" => context.ratings[song.id]
    }
  end

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
      "starred" => artist.agent_id && timestamp(context.starred[artist.agent_id])
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
  def timestamp(%DateTime{} = at), do: DateTime.to_iso8601(at)
end
