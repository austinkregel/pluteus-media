defmodule Pluteus.DiscIdTest do
  @moduledoc """
  A cue sheet yields a disc table of contents, which hashes to the disc ID MusicBrainz
  holds for the disc (spec-05 §9.1, criterion 32).

  The IDs are the ones the publisher and libdiscid publish beside their inputs, so what is
  under test is agreement with them and not with this module's own reading of the
  algorithm.
  """

  use ExUnit.Case, async: true

  alias Pluteus.DiscId
  alias Pluteus.Ingest.Cue

  describe "the ID a table of contents hashes to" do
    test "the audio CD in MusicBrainz's Disc ID Calculation" do
      toc = %{
        first: 1,
        last: 6,
        leadout: 95_462,
        offsets: [150, 15_363, 32_314, 46_592, 63_414, 80_489]
      }

      assert DiscId.id(toc) == "49HHV7Eb8UKF3aQiNmu1GR8vKTY-"
    end

    test "the Enhanced CD there, whose data track the ID leaves out" do
      toc = %{
        first: 1,
        last: 7,
        leadout: 114_574,
        offsets: [150, 14_109, 33_586, 53_077, 65_781, 77_892, 99_174]
      }

      assert DiscId.id(toc) == "BPnh1KU.hea1C.KMYWLGZkHJr0w-"
    end

    test "libdiscid's own test disc, of twenty-two tracks" do
      offsets =
        ~w(150 9700 25887 39297 53795 63735 77517 94877 107270 123552 135522 148422 161197
           174790 192022 205545 218010 228700 239590 255470 266932 288750)
        |> Enum.map(&String.to_integer/1)

      assert DiscId.id(%{first: 1, last: 22, leadout: 303_602, offsets: offsets}) ==
               "xUp1F2NkfP8s8jaeFn_Av3jNEI4-"
    end

    test "the disc the web service documents its TOC lookup with" do
      offsets =
        ~w(150 22767 41887 58317 72102 91375 104652 115380 132165 143932 159870 174597)
        |> Enum.map(&String.to_integer/1)

      assert DiscId.id(%{first: 1, last: 12, leadout: 267_257, offsets: offsets}) ==
               "I5l9cCSFccLKFEKS.7wqSZAorPU-"
    end
  end

  # The audio CD above, ripped to one file: each INDEX 01 is its offset less 150 sectors,
  # and the file is 95312 sectors of 588 samples.
  @sheet """
  PERFORMER "An artist"
  TITLE "A release"
  FILE "A release.flac" WAVE
    TRACK 01 AUDIO
      TITLE "One"
      INDEX 01 00:00:00
    TRACK 02 AUDIO
      INDEX 00 03:20:00
      INDEX 01 03:22:63
    TRACK 03 AUDIO
      INDEX 01 07:08:64
    TRACK 04 AUDIO
      INDEX 01 10:19:17
    TRACK 05 AUDIO
      INDEX 01 14:03:39
    TRACK 06 AUDIO
      INDEX 01 17:51:14
  """

  @samples 95_312 * 588

  describe "§9.1. A cue sheet and its file's length yield the table of contents" do
    test "whose ID is the disc's" do
      assert {:ok, toc} = DiscId.toc(Cue.parse(@sheet).tracks, @samples)

      assert toc == %{
               first: 1,
               last: 6,
               leadout: 95_462,
               offsets: [150, 15_363, 32_314, 46_592, 63_414, 80_489]
             }

      assert DiscId.id(toc) == "49HHV7Eb8UKF3aQiNmu1GR8vKTY-"
    end

    test "each track is read to the frame, with its file and type" do
      [first, second | _] = Cue.parse(@sheet).tracks

      assert %{number: 1, start_frames: 0, file: "A release.flac", type: "AUDIO"} = first
      assert %{number: 2, start_frames: 15_213, start_ms: 202_840, pregap_frames: 0} = second
    end

    test "a PREGAP is on the disc and not in the file, so it moves what follows" do
      sheet = String.replace(@sheet, "TRACK 03 AUDIO\n", "TRACK 03 AUDIO\n    PREGAP 00:02:00\n")
      {:ok, toc} = DiscId.toc(Cue.parse(sheet).tracks, @samples)

      assert toc.offsets == [150, 15_363, 32_464, 46_742, 63_564, 80_639]
      assert toc.leadout == 95_612
    end

    test "audio before the first track, kept in the file, places track one later" do
      sheet =
        String.replace(@sheet, "INDEX 01 00:00:00", "INDEX 00 00:00:00\n    INDEX 01 00:01:00")

      {:ok, toc} = DiscId.toc(Cue.parse(sheet).tracks, @samples)
      assert hd(toc.offsets) == 225
    end

    test "a data track after the audio, in a file of its own, is left out" do
      sheet = @sheet <> ~s(FILE "data.bin" BINARY\n  TRACK 07 MODE1/2352\n    INDEX 01 00:00:00\n)
      {:ok, toc} = DiscId.toc(Cue.parse(sheet).tracks, @samples)

      assert toc.last == 6
      assert DiscId.id(toc) == "49HHV7Eb8UKF3aQiNmu1GR8vKTY-"
    end
  end

  describe "§9.1. What a cue sheet does not say, no ID is computed from" do
    test "a data track first, whose length every audio offset depends on" do
      sheet = String.replace(@sheet, "TRACK 01 AUDIO", "TRACK 01 MODE1/2352")
      assert DiscId.toc(Cue.parse(sheet).tracks, @samples) == {:error, :data_track_first}
    end

    test "a data track in the same file as the audio" do
      sheet = @sheet <> "  TRACK 07 MODE1/2352\n    INDEX 01 20:00:00\n"
      assert DiscId.toc(Cue.parse(sheet).tracks, @samples) == {:error, :data_track_in_audio_file}
    end

    test "a data track between audio tracks" do
      sheet = String.replace(@sheet, "TRACK 03 AUDIO", "TRACK 03 MODE1/2352")
      assert DiscId.toc(Cue.parse(sheet).tracks, @samples) == {:error, :data_track_between_audio}
    end

    test "audio in several files, whose lengths the sheet does not give" do
      sheet =
        String.replace(@sheet, "  TRACK 04 AUDIO", ~s(FILE "four.flac" WAVE\n  TRACK 04 AUDIO))

      assert DiscId.toc(Cue.parse(sheet).tracks, @samples) == {:error, :several_files}
    end

    test "a track whose type is not stated" do
      sheet = String.replace(@sheet, "TRACK 05 AUDIO", "TRACK 05")
      assert DiscId.toc(Cue.parse(sheet).tracks, @samples) == {:error, :track_type_not_stated}
    end

    test "a file that is not a whole number of sectors" do
      assert DiscId.toc(Cue.parse(@sheet).tracks, @samples + 100) ==
               {:error, {:not_whole_sectors, 100}}
    end

    test "tracks that do not rise" do
      sheet = String.replace(@sheet, "INDEX 01 07:08:64", "INDEX 01 01:00:00")
      assert DiscId.toc(Cue.parse(sheet).tracks, @samples) == {:error, :malformed}
    end
  end
end
