defmodule Pluteus.MusicFixtures do
  @moduledoc """
  A small music library, placed and normalized by the real pipeline, and a
  client key to reach it on the OpenSubsonic surface.

  "Kind of Blue" holds two tracks credited to "Miles Davis" as album artist:
  "So What" with a picture embedded and an LRC lyrics companion, and "Freddie
  Freeloader" tagged Jazz. A `cover.png` in the album's directory is its cover
  art. An untagged WAV is a release of its own.
  """

  import Ecto.Query, only: [from: 2]
  import Pluteus.IngestFixtures

  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.ManifestationPart
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Ingest.Place
  alias Pluteus.Repo

  @lyrics """
  [ar:Miles Davis]
  [ti:So What]
  [00:01.50]First line
  [00:03.25][00:07.00]Twice sung
  [00:00.50]Count in
  """

  @spec lyrics() :: String.t()
  def lyrics, do: @lyrics

  @doc """
  Places the library and returns its identifiers: `albums` and `songs` by
  title, and the bytes of the cover companion.
  """
  @spec library!() :: map()
  def library! do
    inbox = inbox!()
    cover = media!(:png)

    files = %{
      "KoB/01 So What.flac" =>
        media!(:flac,
          art: true,
          tags: kind_of_blue(%{"title" => "So What", "track" => "1", "genre" => "Modal"})
        ),
      "KoB/02 Freddie.flac" =>
        media!(:flac,
          tags:
            kind_of_blue(%{"title" => "Freddie Freeloader", "track" => "2", "genre" => "Jazz"})
        ),
      "KoB/cover.png" => cover,
      "KoB/01 So What.lrc" => @lyrics,
      "loose/untitled.wav" => media!(:wav)
    }

    for {path, bytes} <- files, do: drop!(inbox, path, bytes)

    placed =
      inbox
      |> acquire_settled!(~U[2026-09-18 12:00:00.000000Z])
      |> acquired()
      |> Enum.map(&Ingest.get_acquisition!/1)

    Place.place_due(inbox)
    Normalize.normalize_due()

    songs =
      for acquisition <- placed,
          acquisition = Ingest.get_acquisition!(acquisition.id),
          acquisition.media_class == :audio,
          into: %{} do
        track = Repo.get!(DigitalItem, acquisition.digital_item_id).manifestation_id
        {Path.basename(acquisition.inbox_path), track}
      end

    %{
      songs: songs,
      albums: Map.new(songs, fn {name, track} -> {name, album_of(track)} end),
      cover: cover
    }
  end

  defp kind_of_blue(tags) do
    Map.merge(
      %{
        "album" => "Kind of Blue",
        "album_artist" => "Miles Davis",
        "artist" => "Miles Davis",
        "date" => "1959"
      },
      tags
    )
  end

  defp album_of(track) do
    Repo.one!(
      from t in ManifestationPart,
        join: m in ManifestationPart,
        on: m.part_id == t.whole_id,
        where: t.part_id == ^track,
        select: m.whole_id
    )
  end
end
