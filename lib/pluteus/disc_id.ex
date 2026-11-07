defmodule Pluteus.DiscId do
  @moduledoc """
  A disc's table of contents, and the MusicBrainz disc ID it hashes to (spec-05 §9.1).

  **The ID** is computed as libdiscid computes it ([MUSICBRAINZ] Disc ID Calculation):
  SHA-1 over the first and last track numbers as two uppercase hexadecimal digits each,
  the lead-out offset as eight, then one offset of eight per track slot from 1 to 99,
  zero beyond the last track — 804 characters in all — encoded in base64 with `+`, `/`
  and `=` written as `.`, `_` and `-`. Every offset is in sectors from the start of the
  disc, 150 sectors before the first track's audio.

  **The table of contents** is read from a cue sheet and the length of the one audio file
  it describes. Each track's offset is 150 plus its `INDEX 01` in frames, plus any
  `PREGAP` before it, which was on the disc and is not in the file; the lead-out is 150
  plus the file's length in sectors of 588 samples, plus every pregap. A data track after
  the audio, as an Enhanced CD carries in a session of its own, is not part of what the ID
  encodes and is left out.

  What a cue sheet does not say, the table of contents is not computed from. The ID is
  not computed where:

    * the first track is data, as on a mixed-mode disc: every audio track's offset then
      depends on the data track's length, which neither the sheet nor the audio states;
    * a data track sits between audio tracks, or in the same file as the audio;
    * the audio tracks are in several files, whose lengths the sheet does not give;
    * a track's type is not stated;
    * the file's length is not a whole number of sectors, which a sector-exact rip always
      is.

  None of these is computed from part of the disc instead, which would name some other
  disc (§9.1).
  """

  @sectors_before_the_first_track 150
  @samples_per_sector 588

  @typedoc "A table of contents: the first and last track, the lead-out, and each offset."
  @type toc :: %{
          first: pos_integer(),
          last: pos_integer(),
          leadout: pos_integer(),
          offsets: [pos_integer()]
        }

  @typedoc "Why a sheet and its file yield no table of contents."
  @type not_computable ::
          :data_track_first
          | :data_track_between_audio
          | :data_track_in_audio_file
          | :several_files
          | :track_type_not_stated
          | :first_track_not_one
          | {:not_whole_sectors, pos_integer()}
          | :malformed

  @doc """
  The disc ID a table of contents hashes to.
  """
  @spec id(toc()) :: String.t()
  def id(%{first: first, last: last, leadout: leadout, offsets: offsets}) do
    slots = offsets ++ List.duplicate(0, 99 - length(offsets))

    hex =
      IO.iodata_to_binary([
        hex(first, 2),
        hex(last, 2),
        hex(leadout, 8),
        Enum.map(slots, &hex(&1, 8))
      ])

    :sha
    |> :crypto.hash(hex)
    |> Base.encode64()
    |> String.replace(["+", "/", "="], fn
      "+" -> "."
      "/" -> "_"
      "=" -> "-"
    end)
  end

  defp hex(value, width),
    do: value |> Integer.to_string(16) |> String.pad_leading(width, "0")

  @doc """
  The table of contents a cue sheet's tracks and the length in samples of the file they
  are in make, where the sheet says enough for one.
  """
  @spec toc([Pluteus.Ingest.Cue.track()], non_neg_integer()) ::
          {:ok, toc()} | {:error, not_computable()}
  def toc(tracks, samples) do
    tracks = Enum.sort_by(tracks, & &1.number)
    {audio, after_audio} = Enum.split_while(tracks, &(&1.type == "AUDIO"))

    with :ok <- typed(tracks),
         :ok <- audio_first(audio),
         :ok <- only_data_after(after_audio),
         {:ok, file} <- one_file(audio),
         :ok <- data_elsewhere(after_audio, file),
         :ok <- first_is_one(audio),
         {:ok, sectors} <- whole_sectors(samples) do
      offsets = offsets(audio)
      leadout = @sectors_before_the_first_track + sectors + pregaps(audio)

      checked(%{first: 1, last: List.last(audio).number, leadout: leadout, offsets: offsets})
    end
  end

  defp typed(tracks) do
    if Enum.any?(tracks, &is_nil(&1.type)), do: {:error, :track_type_not_stated}, else: :ok
  end

  defp audio_first([]), do: {:error, :data_track_first}
  defp audio_first(_audio), do: :ok

  defp only_data_after(after_audio) do
    if Enum.any?(after_audio, &(&1.type == "AUDIO")),
      do: {:error, :data_track_between_audio},
      else: :ok
  end

  defp one_file(audio) do
    case audio |> Enum.map(& &1.file) |> Enum.uniq() do
      [file] -> {:ok, file}
      _several -> {:error, :several_files}
    end
  end

  defp data_elsewhere(after_audio, file) do
    if Enum.any?(after_audio, &(&1.file == file)),
      do: {:error, :data_track_in_audio_file},
      else: :ok
  end

  defp first_is_one([%{number: 1} | _rest]), do: :ok
  defp first_is_one(_audio), do: {:error, :first_track_not_one}

  defp whole_sectors(samples) do
    case rem(samples, @samples_per_sector) do
      0 -> {:ok, div(samples, @samples_per_sector)}
      remainder -> {:error, {:not_whole_sectors, remainder}}
    end
  end

  # Each track's offset carries every pregap up to and including its own, since a pregap
  # comes before the track's INDEX 01.
  defp offsets(audio) do
    {offsets, _pregaps} =
      Enum.map_reduce(audio, 0, fn track, pregaps ->
        pregaps = pregaps + track.pregap_frames
        {@sectors_before_the_first_track + track.start_frames + pregaps, pregaps}
      end)

    offsets
  end

  defp pregaps(audio), do: audio |> Enum.map(& &1.pregap_frames) |> Enum.sum()

  # MusicBrainz accepts a table of contents whose offsets rise strictly, whose lead-out
  # follows the last, and which has at most 99 tracks numbered from one without a gap.
  defp checked(%{last: last, leadout: leadout, offsets: offsets} = toc) do
    rising = offsets |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [a, b] -> a < b end)

    if rising and leadout > List.last(offsets) and last == length(offsets) and last <= 99,
      do: {:ok, toc},
      else: {:error, :malformed}
  end
end
