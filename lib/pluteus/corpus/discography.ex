defmodule Pluteus.Corpus.Discography do
  @moduledoc """
  Answers identifiers from the household's copy of MusicBrainz (spec-05 §5.5, §9.1),
  issuing no query outside the house.

  **An identifier merged into another is answered with the one it now is.** MusicBrainz
  keeps a redirect for every identifier it merges away, and a file tagged before the merge
  carries the old one; answered with the current one, two files naming one recording by
  its two identifiers name it alike.

  **A corpus holding no row is silent** (§5.2): `nil` or an empty list, and never an
  error.
  """

  alias Pluteus.Corpus.Repo

  # The tables answering each identifier scheme, which each have a redirect table of the
  # same name.
  @tables %{
    "musicbrainz_recording" => "recording",
    "musicbrainz_track" => "track",
    "musicbrainz_release" => "release",
    "musicbrainz_release_group" => "release_group",
    "musicbrainz_work" => "work"
  }

  @typedoc "What the corpus holds for an identifier."
  @type held :: %{String.t() => String.t() | nil}

  @doc """
  What the corpus holds for an MBID in `scheme`: the identifier it now is, its name, and
  the one asked for where that was merged away. A malformed identifier is never asked;
  the caller checks the form first (§4.4).
  """
  @spec identifier(String.t(), Ecto.UUID.t()) :: held() | nil
  def identifier(scheme, gid) do
    table = Map.fetch!(@tables, scheme)

    %{rows: rows} =
      Repo.query!(
        """
        SELECT e.gid::text, e.name, NULL FROM musicbrainz.#{table} e WHERE e.gid = $1
        UNION ALL
        SELECT e.gid::text, e.name, r.gid::text
          FROM musicbrainz.#{table}_gid_redirect r
          JOIN musicbrainz.#{table} e ON e.id = r.new_id
         WHERE r.gid = $1
        """,
        [dump_uuid(gid)]
      )

    case rows do
      [] -> nil
      [[current, name, merged]] -> %{"mbid" => current, "name" => name, "merged_from" => merged}
    end
  end

  @doc """
  The recordings an ISRC was given to, by their MBIDs. Distributors give their own ISRCs,
  and some have been given to several recordings, so this is a list.
  """
  @spec recordings_with_isrc(String.t()) :: [held()]
  def recordings_with_isrc(isrc) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT DISTINCT r.gid::text, r.name
          FROM musicbrainz.isrc i
          JOIN musicbrainz.recording r ON r.id = i.recording
         WHERE i.isrc = $1
         ORDER BY 1
        """,
        [isrc]
      )

    Enum.map(rows, fn [mbid, name] -> %{"mbid" => mbid, "name" => name} end)
  end

  @doc """
  Every medium a disc ID is attached to: the medium, its position in its release, the
  release, and each track's recording by position. Several releases are often pressed
  from one table of contents, so this is a list.
  """
  @spec media_with_disc(String.t()) :: [map()]
  def media_with_disc(discid) do
    %{rows: media} =
      Repo.query!(
        """
        SELECT DISTINCT m.id, m.gid::text, m.position, r.gid::text, r.name
          FROM musicbrainz.cdtoc c
          JOIN musicbrainz.medium_cdtoc mc ON mc.cdtoc = c.id
          JOIN musicbrainz.medium m ON m.id = mc.medium
          JOIN musicbrainz.release r ON r.id = m.release
         WHERE c.discid = $1
         ORDER BY 2
        """,
        [discid]
      )

    for [id, medium, position, release, name] <- media do
      %{
        "medium" => medium,
        "position" => position,
        "release" => %{"mbid" => release, "name" => name},
        "tracks" => tracks_of(id)
      }
    end
  end

  defp tracks_of(medium_id) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT t.position, t.gid::text, t.name, r.gid::text, r.name
          FROM musicbrainz.track t
          JOIN musicbrainz.recording r ON r.id = t.recording
         WHERE t.medium = $1 AND NOT t.is_data_track
         ORDER BY t.position
        """,
        [medium_id]
      )

    for [position, track, name, recording, recording_name] <- rows do
      %{
        "position" => position,
        "track" => %{"mbid" => track, "name" => name},
        "recording" => %{"mbid" => recording, "name" => recording_name}
      }
    end
  end

  defp dump_uuid(gid), do: gid |> Ecto.UUID.dump!()
end
