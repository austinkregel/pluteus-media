defmodule Pluteus.Matching.MusicTest do
  @moduledoc """
  A piece of music is matched by the identifiers it carries against the MusicBrainz copy
  the household holds (spec-05 §7, §8.2, §8.4, §9.1; criteria 6, 12, 18, 19, 23, 24, 25,
  32, 33).

  Tracks are placed by the real pipeline from files made by ffmpeg, and run through the
  key, resolve and apply stages against a small dump imported the way a real one is.

  Not async: holding a snapshot exchanges the `musicbrainz` schema itself.
  """

  use Pluteus.DataCase, async: false

  import Bitwise
  import Ecto.Query, only: [from: 2]
  import Pluteus.IngestFixtures
  import Pluteus.MusicBrainzFixtures

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Aggregation
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Corpus
  alias Pluteus.Dedup.Candidate
  alias Pluteus.DiscId
  alias Pluteus.Ingest
  alias Pluteus.Lifecycle
  alias Pluteus.Matching.Equation
  alias Pluteus.Matching.MatchRecord
  alias Pluteus.Matching.Music
  alias Pluteus.Principals

  @t0 ~U[2026-11-07 12:00:00.000000Z]

  @song "8f3471b5-7e6a-48da-86a9-c1c07a0f47ae"
  @other "1b7e3f7e-5a7b-4d1f-9c3a-2b6f8c9d0e1f"
  @third "2c8f4a8f-6b8c-4e2a-8d4b-3c7a9dae1f2a"
  @merged "9d4b6f2a-0c1d-4e5f-a6b7-c8d9e0f1a2b3"
  @album "a1b2c3d4-e5f6-4789-8abc-def012345678"
  @compilation "b2c3d4e5-f6a7-4890-9bcd-ef0123456789"
  @ripped "c3d4e5f6-a7b8-4901-8cde-f01234567890"
  @album_group "d4e5f6a7-b8c9-4012-9def-012345678901"
  @album_track "e5f6a7b8-c9d0-4123-8ef0-123456789012"
  @song_work "f6a7b8c9-d0e1-4234-9f01-234567890123"
  @unheld "00000000-0000-4000-8000-000000000001"

  @isrc "USRC17607839"
  @shared_isrc "GBAYE0601498"

  # A three-track disc ripped to one file of 6750 sectors.
  @toc %{first: 1, last: 3, leadout: 6900, offsets: [150, 2400, 4650]}
  @sectors 6750

  defp corpus_rows do
    %{
      "recording" => [
        recording(1, @song, "Song"),
        recording(2, @other, "Other"),
        recording(3, @third, "Third")
      ],
      "recording_gid_redirect" => [redirect(@merged, 1)],
      "release" => [
        release(10, @album, 100, "Album"),
        release(11, @compilation, 101, "Compilation"),
        release(12, @ripped, 102, "Ripped")
      ],
      "release_group" => [
        release_group(100, @album_group, "Album"),
        release_group(101, "e1f2a3b4-c5d6-4789-8abc-def012345670", "Compilation"),
        release_group(102, "f2a3b4c5-d6e7-4890-9bcd-ef0123456781", "Ripped")
      ],
      "medium" => [
        medium(20, "0a1b2c3d-4e5f-4a6b-8c7d-8e9f0a1b2c3d", 10, 1, 1),
        medium(21, "1b2c3d4e-5f6a-4b7c-9d8e-9f0a1b2c3d4e", 11, 1, 1),
        medium(22, "2c3d4e5f-6a7b-4c8d-ae9f-0a1b2c3d4e5f", 12, 1, 3)
      ],
      "track" => [
        track(30, @album_track, 1, 20, 1, "Song"),
        track(31, "3d4e5f6a-7b8c-4d9e-8f0a-1b2c3d4e5f6a", 1, 21, 1, "Song"),
        track(32, "4e5f6a7b-8c9d-4e0f-9a1b-2c3d4e5f6a7b", 1, 22, 1, "Song"),
        track(33, "5f6a7b8c-9d0e-4f1a-8b2c-3d4e5f6a7b8c", 2, 22, 2, "Other"),
        track(34, "6a7b8c9d-0e1f-4a2b-9c3d-4e5f6a7b8c9d", 3, 22, 3, "Third")
      ],
      "work" => [work(40, @song_work, "Song")],
      "isrc" => [isrc(1, 1, @isrc), isrc(2, 1, @shared_isrc), isrc(3, 2, @shared_isrc)],
      "cdtoc" => [cdtoc(50, DiscId.id(@toc), @toc.leadout, @toc.offsets)],
      "medium_cdtoc" => [medium_cdtoc(60, 22, 50)]
    }
  end

  setup do
    _system = Principals.system!()
    on_exit(fn -> File.rm_rf!(Path.join(Corpus.directory(), "musicbrainz")) end)
    %{inbox: inbox!(), snapshot: held!(corpus_rows())}
  end

  defp place!(inbox, files) do
    prefix = unique_prefix()
    for {path, bytes} <- files, do: drop!(inbox, Path.join(prefix, path), bytes)
    ids = inbox |> acquire_settled!(@t0) |> acquired()
    place_all!(inbox)
    Map.new(ids, &{Path.relative_to(Ingest.get_acquisition!(&1).inbox_path, prefix), &1})
  end

  defp track_tags(album, release, tags) do
    Map.merge(
      %{
        "album" => album,
        "album_artist" => "An artist",
        "musicbrainz_albumid" => release,
        "track" => "1"
      },
      tags
    )
  end

  defp run_stages! do
    Music.key_due()
    Music.resolve_due()
    Music.apply_due()
  end

  defp manifestation(acquisition_id),
    do:
      Repo.get!(DigitalItem, Ingest.get_acquisition!(acquisition_id).digital_item_id).manifestation_id

  defp expression(acquisition_id) do
    [expression] = acquisition_id |> manifestation() |> Catalog.expressions_in()
    expression
  end

  defp identifiers(res, scheme) do
    Repo.all(
      from n in Nomen,
        where: n.res_id == ^res and n.scheme == ^scheme,
        order_by: n.nomen_string,
        select: n.nomen_string
    )
  end

  defp id3_frame(id, body), do: id <> <<byte_size(body)::32, 0, 0>> <> body

  defp synchsafe(n),
    do: <<n >>> 21 &&& 0x7F, n >>> 14 &&& 0x7F, n >>> 7 &&& 0x7F, n &&& 0x7F>>

  defp match_findings,
    do: Enum.filter(Ingest.open_findings(), &(&1.stage == :match))

  describe "§8.2. An identifier a holding carries is written at the level it identifies" do
    test "a track's recording, track, release, release group and work", %{inbox: inbox} do
      %{"song.flac" => id} =
        place!(inbox, %{
          "song.flac" =>
            media!(:flac,
              tags:
                track_tags("Album", @album, %{
                  "musicbrainz_trackid" => @song,
                  "musicbrainz_releasetrackid" => @album_track,
                  "musicbrainz_releasegroupid" => @album_group,
                  "musicbrainz_workid" => @song_work
                })
            )
        })

      run_stages!()

      track = manifestation(id)
      recording = expression(id)
      [%{whole_id: medium}] = Catalog.wholes_of(track)
      [%{whole_id: release}] = Catalog.wholes_of(medium)
      [release_expression] = Catalog.expressions_in(release)

      assert identifiers(recording.id, "musicbrainz_recording") == [@song]
      assert identifiers(track, "musicbrainz_track") == [@album_track]
      assert identifiers(recording.work_id, "musicbrainz_work") == [@song_work]
      assert identifiers(release, "musicbrainz_release") == [@album]

      assert identifiers(release_expression.work_id, "musicbrainz_release_group") == [
               @album_group
             ]

      [nomen] =
        Repo.all(
          from n in Nomen,
            where: n.res_id == ^recording.id and n.scheme == "musicbrainz_recording"
        )

      assert nomen.provenance == :automatic

      assert Catalog.nomens_for(nomen.assigner_id) |> Enum.map(& &1.nomen_string) == [
               "MusicBrainz"
             ]

      assert match_findings() == []
    end

    test "an MP3's recording, from the UFID frame ffprobe does not report", %{inbox: inbox} do
      mp3 = media!(:mp3, untagged: true)
      {:ok, length} = Pluteus.Id3.tag_bytes(mp3)
      audio = binary_part(mp3, length, byte_size(mp3) - length)

      # The album and its artist, as a tagged MP3 states them, and the recording in UFID.
      frames =
        id3_frame("TALB", <<0>> <> "Album") <>
          id3_frame("TPE2", <<0>> <> "An artist") <>
          id3_frame("UFID", "http://musicbrainz.org" <> <<0>> <> @song)

      tagged = "ID3" <> <<3, 0, 0>> <> synchsafe(byte_size(frames)) <> frames <> audio

      %{"song.mp3" => id} = place!(inbox, %{"song.mp3" => tagged})
      run_stages!()

      assert identifiers(expression(id).id, "musicbrainz_recording") == [@song]
    end

    test "an identifier merged into another is written as the one it now is", %{inbox: inbox} do
      %{"song.flac" => id} =
        place!(inbox, %{
          "song.flac" =>
            media!(:flac, tags: track_tags("Album", @album, %{"musicbrainz_trackid" => @merged}))
        })

      run_stages!()

      assert identifiers(expression(id).id, "musicbrainz_recording") == [@song]
    end
  end

  describe "§9.1. ISRCs" do
    test "several on one expression are ordinary, and one naming one recording names it", %{
      inbox: inbox
    } do
      %{"song.flac" => id} =
        place!(inbox, %{
          "song.flac" =>
            media!(:flac,
              tags: track_tags("Album", @album, %{"isrc" => "#{@isrc};#{@shared_isrc}"})
            )
        })

      run_stages!()
      recording = expression(id).id

      assert identifiers(recording, "isrc") == [@shared_isrc, @isrc] |> Enum.sort()
      # The shared ISRC is given to two recordings, so it names neither; the other names one.
      assert identifiers(recording, "musicbrainz_recording") == [@song]
      assert match_findings() == []
    end

    test "one given to several recordings names none of them", %{inbox: inbox} do
      %{"song.flac" => id} =
        place!(inbox, %{
          "song.flac" =>
            media!(:flac, tags: track_tags("Album", @album, %{"isrc" => @shared_isrc}))
        })

      run_stages!()
      recording = expression(id).id

      assert identifiers(recording, "isrc") == [@shared_isrc]
      assert identifiers(recording, "musicbrainz_recording") == []
    end
  end

  describe "§4.4, §5.4, §11. What is not written" do
    test "a malformed identifier is a finding and is not written", %{inbox: inbox} do
      %{"song.flac" => id} =
        place!(inbox, %{
          "song.flac" =>
            media!(:flac,
              tags: track_tags("Album", @album, %{"musicbrainz_trackid" => "not-an-mbid"})
            )
        })

      run_stages!()

      assert [%{kind: "identifier_malformed", detail: detail}] = match_findings()
      assert detail == %{"scheme" => "musicbrainz_recording", "values" => ["not-an-mbid"]}
      assert identifiers(expression(id).id, "musicbrainz_recording") == []
    end

    test "two recordings tagged on one file contradict each other, and neither is written", %{
      inbox: inbox
    } do
      %{"song.flac" => id} =
        place!(inbox, %{
          "song.flac" =>
            media!(:flac,
              tags: track_tags("Album", @album, %{"musicbrainz_trackid" => "#{@song};#{@other}"})
            )
        })

      run_stages!()

      assert [%{kind: "identifiers_contradict", detail: %{"scheme" => "musicbrainz_recording"}}] =
               match_findings()

      assert identifiers(expression(id).id, "musicbrainz_recording") == []
    end

    test "an identifier the corpus holds nothing for is silent, and not asked again", %{
      inbox: inbox
    } do
      %{"song.flac" => id} =
        place!(inbox, %{
          "song.flac" =>
            media!(:flac, tags: track_tags("Album", @album, %{"musicbrainz_trackid" => @unheld}))
        })

      run_stages!()
      recording = expression(id).id

      assert identifiers(recording, "musicbrainz_recording") == []
      assert match_findings() == []

      assert %{state: :empty} =
               Repo.one!(
                 from m in MatchRecord,
                   where: m.res_id == ^recording and m.scheme == "musicbrainz_recording"
               )

      assert Music.key_due() == []
      assert Music.resolve_due() == []
    end
  end

  describe "33. The same recording on an album and on a compilation" do
    setup %{inbox: inbox} do
      placed =
        place!(inbox, %{
          "album/song.flac" =>
            media!(:flac, tags: track_tags("Album", @album, %{"musicbrainz_trackid" => @song})),
          "compilation/song.flac" =>
            media!(:flac,
              frequency: 660,
              tags: track_tags("Compilation", @compilation, %{"musicbrainz_trackid" => @song})
            )
        })

      %{album: placed["album/song.flac"], compilation: placed["compilation/song.flac"]}
    end

    test "is one expression and one work, and remains two track manifestations", %{
      album: album,
      compilation: compilation
    } do
      album_track = manifestation(album)
      compilation_track = manifestation(compilation)
      [compiled] = Catalog.expressions_in(compilation_track)

      [%{aggregating_expression_id: compiling}] =
        Repo.all(from a in Aggregation, where: a.aggregated_expression_id == ^compiled.id)

      run_stages!()

      [one] = Catalog.expressions_in(album_track)
      assert Catalog.expressions_in(compilation_track) == [one]
      assert album_track != compilation_track

      assert Enum.sort(Enum.map(Catalog.manifestations_of(one.id), & &1.id)) ==
               Enum.sort([album_track, compilation_track])

      # The compilation still holds the track, now as the one expression.
      assert Repo.exists?(
               from a in Aggregation,
                 where:
                   a.aggregating_expression_id == ^compiling and
                     a.aggregated_expression_id == ^one.id
             )

      assert {:recycled, _, _} = Lifecycle.state(compiled.id)
      assert {:recycled, _, _} = Lifecycle.state(compiled.work_id)
    end

    test "is reported, decided by the System principal, and undone exactly", %{
      album: album,
      compilation: compilation,
      actor: member
    } do
      [compiled] = compilation |> manifestation() |> Catalog.expressions_in()
      run_stages!()

      assert [%{kind: "equated", detail: detail}] = match_findings()
      assert detail["decision"] == "same_expression"
      assert detail["identifier"] == %{"scheme" => "musicbrainz_recording", "value" => @song}

      candidate = Repo.get!(Candidate, detail["candidate"])
      assert candidate.signal == :matching
      assert candidate.decision == :same_expression
      assert candidate.decided_by == Principals.system!().id

      assert {:ok, %{decision: :distinct}} = Equation.undo(detail, member.id)

      assert compilation |> manifestation() |> Catalog.expressions_in() == [compiled]
      assert {:live, _} = Lifecycle.state(compiled.id)
      assert {:live, _} = Lifecycle.state(compiled.work_id)
      refute expression(album).id == compiled.id

      assert Repo.exists?(
               from a in Aggregation, where: a.aggregated_expression_id == ^compiled.id
             )
    end

    test "is not performed again once a member has decided the two distinct", %{
      album: album,
      compilation: compilation,
      actor: member
    } do
      run_stages!()
      [%{detail: detail}] = match_findings()
      {:ok, _} = Equation.undo(detail, member.id)

      # A newer snapshot makes every match due again.
      later = corpus_rows() |> dump() |> verified(~D[2026-12-04]) |> import_whole()
      assert later.state == :imported
      run_stages!()

      refute expression(album).id == expression(compilation).id

      declined =
        Repo.all(
          from m in MatchRecord,
            where: m.scheme == "musicbrainz_recording" and is_nil(m.superseded_by_id),
            where: m.state == :applied,
            select: m.conclusion
        )
        |> Enum.flat_map(& &1["equations"])

      assert Enum.any?(declined, &(&1["outcome"] == "declined"))
    end
  end

  describe "32. A cue sheet's disc ID matches a medium as an equality" do
    test "and the one medium it names gives the release, and each track's recording", %{
      inbox: inbox
    } do
      sheet = """
      PERFORMER "An artist"
      TITLE "Ripped"
      FILE "ripped.flac" WAVE
        TRACK 01 AUDIO
          TITLE "Song"
          INDEX 01 00:00:00
        TRACK 02 AUDIO
          TITLE "Other"
          INDEX 01 00:30:00
        TRACK 03 AUDIO
          TITLE "Third"
          INDEX 01 01:00:00
      """

      %{"ripped.flac" => id} =
        place!(inbox, %{
          "ripped.flac" => media!(:cd_flac, sectors: @sectors, tags: %{"album" => "Ripped"}),
          "ripped.cue" => sheet
        })

      run_stages!()

      release = manifestation(id)
      [%{part_id: medium}] = Catalog.parts_of(release)

      assert identifiers(medium, "musicbrainz_disc") == [DiscId.id(@toc)]
      assert identifiers(release, "musicbrainz_release") == [@ripped]

      recordings =
        for part <- Catalog.parts_of(medium) do
          [expression] = Catalog.expressions_in(part.part_id)
          identifiers(expression.id, "musicbrainz_recording")
        end

      assert recordings == [[@song], [@other], [@third]]
      assert match_findings() == []
    end

    test "a file that is not a CD's audio yields no disc ID, and no finding", %{inbox: inbox} do
      # One channel: not what a CD holds, however exactly it was ripped.
      sheet = "FILE \"mono.flac\" WAVE\n  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n"

      %{"mono.flac" => id} =
        place!(inbox, %{
          "mono.flac" => media!(:flac, tags: %{"album" => "Mono"}),
          "mono.cue" => sheet
        })

      run_stages!()
      [%{part_id: medium}] = Catalog.parts_of(manifestation(id))

      assert identifiers(medium, "musicbrainz_disc") == []

      assert %{state: :empty, query: query, conclusion: %{"not_computable" => "not_cd_audio"}} =
               Repo.one!(
                 from m in MatchRecord,
                   where: m.res_id == ^medium and m.scheme == "musicbrainz_disc"
               )

      assert query == %{}
      assert match_findings() == []
    end
  end
end
