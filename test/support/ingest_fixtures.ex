defmodule Pluteus.IngestFixtures do
  @moduledoc """
  Inboxes, real media, and passes over them.

  Every test gets an inbox of its own, and every byte an acquisition moves into
  primary storage is removed when the test exits. Media are made by ffmpeg from
  its own test sources, so a file has the codecs, streams, dispositions and tags
  the test names and nothing borrowed.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Pluteus.Ingest
  alias Pluteus.Storage

  @settle 60

  @doc """
  A fresh, empty inbox, removed when the test exits.
  """
  @spec inbox!() :: Path.t()
  def inbox! do
    inbox =
      :pluteus
      |> Application.fetch_env!(Pluteus.Ingest)
      |> Keyword.fetch!(:inbox)
      |> Path.join("t#{System.unique_integer([:positive])}")

    File.mkdir_p!(inbox)
    on_exit(fn -> File.rm_rf!(inbox) end)
    inbox
  end

  @doc """
  A directory name no other test will use, to drop a set of files under.

  `inbox_sightings` is keyed on the relative path and `acquisitions` carries a unique
  index on it, so two async tests dropping the same relative path contend on those rows:
  each holds its own uncommitted, and the second waits for the first to finish. The
  Repo's timeout is longer than a test's, so a slow test holding a common path does not
  fail — it makes some other test using that path fail instead, somewhere else.

  One prefix per set rather than one per file, so files dropped together keep the
  relative order their names give them, and a directory's companions still share a
  directory.
  """
  @spec unique_prefix() :: String.t()
  def unique_prefix, do: "t#{System.unique_integer([:positive])}"

  @doc """
  An NES cartridge dump in the iNES container.

  Four magic bytes and a twelve-byte header, then the one program and one character bank
  the header declares, filled with `fill`. Two dumps built from different fills differ in
  every byte of their content while identifying as one format, which is the shape spec-04
  criterion 40 turns on: nothing in the bytes says the two are one game.

  Nobody's game, and no emulator's: the banks hold no instructions.
  """
  @spec ines_rom(binary()) :: binary()
  def ines_rom(fill) when byte_size(fill) == 1 do
    header = "NES\x1a" <> <<1, 1, 0, 0>> <> :binary.copy(<<0>>, 8)

    header <> :binary.copy(fill, 16_384) <> :binary.copy(fill, 8_192)
  end

  @doc """
  Writes bytes into the inbox at a relative path.
  """
  @spec drop!(Path.t(), String.t(), binary()) :: Path.t()
  def drop!(inbox, relative, bytes) do
    path = Path.join(inbox, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)
    path
  end

  @doc """
  Two passes a settle interval apart, so every file already in the inbox is
  seen once and then acquired. Returns the second pass's report.
  """
  @spec acquire_settled!(Path.t(), DateTime.t()) :: map()
  def acquire_settled!(inbox, from \\ DateTime.utc_now()) do
    first = pass!(inbox, from)
    second = pass!(inbox, DateTime.add(from, @settle, :second))
    %{second | files: first.files ++ second.files, recovered: first.recovered ++ second.recovered}
  end

  @doc """
  One pass over the inbox at a given moment. Bytes it moves are removed when
  the test exits.
  """
  @spec pass!(Path.t(), DateTime.t()) :: map()
  def pass!(inbox, now) do
    report = Ingest.acquire(inbox, now: now, settle_seconds: @settle)

    for {_path, {:acquired, {id, _outcome}}} <- report.files do
      cleanup(id)
    end

    report
  end

  @doc """
  The acquisition identifiers a report says were created.
  """
  @spec acquired(map()) :: [Ecto.UUID.t()]
  def acquired(report), do: for({_path, {:acquired, {id, _}}} <- report.files, do: id)

  @doc """
  Removes an identifier's bytes when the test exits.
  """
  @spec cleanup(Ecto.UUID.t()) :: :ok
  def cleanup(id) do
    location = Ingest.location_for(id)
    on_exit(fn -> Storage.delete(location) end)
  end

  @doc """
  The bytes of a media file made by ffmpeg.

  Recipes:

    * `:flac` — two seconds of tone; `tags:` become container tags, and
      `art: true` embeds a JPEG as cover art
    * `:mp3` — lossy audio
    * `:bursts` — a tone in short bursts separated by silence
    * `:wav` — PCM audio
    * `:film` — a Matroska container of lossy H.264 video and the audio
      streams `audio:` lists as `{language, codec, disposition}`; by default
      Russian FLAC and an English AAC commentary
    * `:film_remuxed` — the default `:film` remuxed with its streams in
      reverse order and its audio re-encoded to PCM, as a normalization might
    * `:ffv1` — lossless video with no audio
    * `:x264_444` — H.264 in the High 4:4:4 Predictive profile, which has a
      lossless mode the probe cannot see
    * `:png`, `:jpeg` — one still frame
  """
  @spec media!(atom(), keyword()) :: binary()
  def media!(recipe, opts \\ []) do
    dir = Path.join(System.tmp_dir!(), "pluteus-media-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      out = Path.join(dir, output_name(recipe))
      ffmpeg!(args(recipe, opts, dir) ++ [out])
      File.read!(out)
    after
      File.rm_rf!(dir)
    end
  end

  defp output_name(:flac), do: "out.flac"
  defp output_name(:bursts), do: "out.flac"
  defp output_name(:mp3), do: "out.mp3"
  defp output_name(:wav), do: "out.wav"
  defp output_name(:film), do: "out.mkv"
  defp output_name(:film_remuxed), do: "out.mkv"
  defp output_name(:ffv1), do: "out.mkv"
  defp output_name(:x264_444), do: "out.mkv"
  defp output_name(:png), do: "out.png"
  defp output_name(:jpeg), do: "out.jpg"
  defp output_name(:large_still), do: "out.png"

  defp args(:flac, opts, dir) do
    art =
      if opts[:art] do
        art = Path.join(dir, "art.jpg")
        ffmpeg!(still() ++ [art])

        ["-i", art, "-map", "0", "-map", "1", "-c:a", "flac", "-c:v", "copy"] ++
          ["-disposition:v", "attached_pic"]
      else
        []
      end

    tone(opts) ++ art ++ tags(opts[:tags] || %{})
  end

  defp args(:mp3, opts, _dir), do: tone(opts) ++ ["-c:a", "libmp3lame"]

  # A 1 kHz tone in 120 ms bursts once a second for 5.3 seconds. Gating blocks
  # that overlap by 75% measure it about 1 LU quieter than blocks that do not,
  # so the overlap BS.1770 requires shows in the result.
  defp args(:bursts, _opts, _dir) do
    expression = "0.4*sin(2*PI*1000*t)*lt(mod(t,1.0),0.12)"
    ["-f", "lavfi", "-i", "aevalsrc=exprs='#{expression}':s=48000:d=5.3"]
  end

  defp args(:wav, opts, _dir), do: tone(opts)

  defp args(:film, opts, _dir) do
    audio = Keyword.get(opts, :audio, [{"rus", "flac", nil}, {"eng", "aac", "comment"}])

    inputs =
      audio
      |> Enum.with_index()
      |> Enum.flat_map(fn {_stream, index} ->
        ["-f", "lavfi", "-i", "sine=frequency=#{300 + index * 100}:duration=1"]
      end)

    maps = Enum.flat_map(0..length(audio), &["-map", "#{&1}"])

    streams =
      audio
      |> Enum.with_index()
      |> Enum.flat_map(fn {{language, codec, disposition}, index} ->
        ["-c:a:#{index}", codec, "-metadata:s:a:#{index}", "language=#{language}"] ++
          ["-disposition:a:#{index}", disposition || "0"]
      end)

    moving() ++
      inputs ++ maps ++ ["-c:v", "libx264", "-pix_fmt", "yuv420p"] ++ streams ++ ["-shortest"]
  end

  defp args(:film_remuxed, _opts, dir) do
    film = Path.join(dir, "film.mkv")
    ffmpeg!(args(:film, [], dir) ++ [film])

    ["-i", film, "-map", "0:2", "-map", "0:1", "-map", "0:0", "-c:v", "copy", "-c:a", "pcm_s16le"] ++
      ["-disposition:a:0", "comment", "-disposition:a:1", "default"]
  end

  defp args(:ffv1, opts, dir),
    do: moving(opts) ++ chapters(opts[:chapters], dir) ++ ["-c:v", "ffv1"]

  defp args(:x264_444, _opts, _dir), do: moving() ++ ["-c:v", "libx264", "-pix_fmt", "yuv444p"]
  defp args(:png, _opts, _dir), do: still()
  defp args(:jpeg, _opts, _dir), do: still()

  # Just past [spec-10] §20's sixteen-megapixel threshold, which is where a graded
  # profile set gives way to a tiled pyramid. Just past rather than well past, because
  # every pixel of it is encoded, decoded and then tiled by whatever uses it.
  defp args(:large_still, _opts, _dir),
    do: ["-f", "lavfi", "-i", "testsrc=size=4100x4000", "-frames:v", "1"]

  defp tone(opts) do
    frequency = Keyword.get(opts, :frequency, 440)
    duration = Keyword.get(opts, :duration, 2)
    ["-f", "lavfi", "-i", "sine=frequency=#{frequency}:duration=#{duration}"]
  end

  defp moving(opts \\ []) do
    duration = Keyword.get(opts, :duration, 1)
    ["-f", "lavfi", "-i", "testsrc=duration=#{duration}:size=64x48:rate=5"]
  end

  defp still, do: ["-f", "lavfi", "-i", "testsrc=size=64x48", "-frames:v", "1"]

  defp tags(tags),
    do: Enum.flat_map(tags, fn {key, value} -> ["-metadata", "#{key}=#{value}"] end)

  # Chapters travel in a metadata file rather than on the command line, so they are
  # written beside the output and read back in as a second input.
  defp chapters(nil, _dir), do: []

  defp chapters(chapters, dir) do
    path = Path.join(dir, "chapters.txt")

    body =
      Enum.map_join(chapters, "\n", fn {title, {from_ms, to_ms}} ->
        """
        [CHAPTER]
        TIMEBASE=1/1000
        START=#{from_ms}
        END=#{to_ms}
        title=#{title}
        """
      end)

    File.write!(path, ";FFMETADATA1\n" <> body)

    ["-i", path, "-map_metadata", "1", "-map_chapters", "1"]
  end

  # Bounded to two threads: the suite runs many of these at once, and ffmpeg's default
  # is a thread per core. Unbounded, a handful of concurrent encodes oversubscribe the
  # machine and the scheduler starvation shows up as unrelated tests timing out.
  defp ffmpeg!(args) do
    arguments = ["-loglevel", "error", "-y", "-threads", "2" | args]

    case System.cmd("ffmpeg", arguments, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> raise "ffmpeg exited #{status}: #{output}"
    end
  end

  @doc """
  A one-page PDF, written by hand.
  """
  @spec pdf() :: binary()
  def pdf do
    """
    %PDF-1.4
    1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
    2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
    3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 10 10]>>endobj
    trailer<</Root 1 0 R>>
    %%EOF
    """
  end

  @doc """
  A scan: dark words on white paper, large enough for OCR to read.

  Rendered rather than drawn, so the test exercises the reader on real glyph shapes
  rather than on text the fixture also wrote out.
  """
  @spec words_on_paper(String.t()) :: binary()
  def words_on_paper(words \\ "Dear Ada") do
    dir = Path.join(System.tmp_dir!(), "pluteus-scan-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      out = Path.join(dir, "scan.png")

      ffmpeg!([
        "-f",
        "lavfi",
        "-i",
        "color=c=white:s=600x200,drawtext=text='#{words}':fontcolor=black:fontsize=64:x=40:y=60",
        "-frames:v",
        "1",
        out
      ])

      File.read!(out)
    after
      File.rm_rf!(dir)
    end
  end

  @doc """
  A JPEG carrying an EXIF `Orientation` tag.

  ffmpeg writes no EXIF, so the APP1 segment is assembled here and spliced in after
  the image's own marker: six bytes of `Exif\\0\\0`, a big-endian TIFF header, and an
  IFD0 of one entry holding tag 0x0112.

  The pixels are `still/0`'s 64 by 48, so a derivative of an image stating 5 to 8 is
  taller than it is wide and one stating 1 to 4 is not.
  """
  @spec oriented_jpeg(1..8) :: binary()
  def oriented_jpeg(orientation) do
    <<0xFF, 0xD8, rest::binary>> = media!(:jpeg)

    ifd =
      <<0x00, 0x01>> <>
        <<0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, orientation::16, 0x00, 0x00>> <>
        <<0x00, 0x00, 0x00, 0x00>>

    exif = "Exif" <> <<0, 0>> <> "MM" <> <<0x00, 0x2A, 0x00, 0x00, 0x00, 0x08>> <> ifd

    <<0xFF, 0xD8>> <> <<0xFF, 0xE1, byte_size(exif) + 2::16>> <> exif <> rest
  end

  @doc """
  A cartridge dump in the iNES container: the four magic bytes, the twelve-byte
  header giving one 16 KiB program bank and one 8 KiB character bank, and banks
  of that size holding nothing.

  The bytes are the container's, not a game's.
  """
  @spec rom() :: binary()
  def rom do
    header = "NES\x1a" <> <<1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>

    header <> :binary.copy(<<0>>, 16_384) <> :binary.copy(<<0>>, 8_192)
  end
end
