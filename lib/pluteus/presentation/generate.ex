defmodule Pluteus.Presentation.Generate do
  @moduledoc """
  Making a derivative from a master's bytes ([spec-10] §11).

  ffmpeg runs here on the BEAM side and not in the analysis sidecar, for two reasons
  the sidecar's own shape decides: its storage mounts are read-only and its root
  filesystem is read-only, so it cannot write a derivative anywhere the deployment
  would find it, and its contract answers measurements rather than bytes.

  **The bytes are written before the row.** `Pluteus.Presentation` records a row only
  where the bytes exist, so the order is: encode to the location the key derives from,
  measure what came out, then record. A crash between the encode and the record leaves
  bytes nothing points at, which the next eviction pass reclaims; the reverse would
  leave a row that serves an empty body.

  Every image derivative has its orientation applied and its metadata stripped
  (criterion 29). ffmpeg applies a JPEG's EXIF orientation on input of its own accord,
  so nothing here adds a filter for it and adding one would turn the image twice.
  `-map_metadata -1` discharges the stripping, and where the source states a turn the
  derivative's axes are checked against it, so that an encoder which stopped
  autorotating would be a finding rather than a library of sideways thumbnails.
  """

  alias Pluteus.Archive
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Asset
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Container
  alias Pluteus.Ingest.Probe
  alias Pluteus.Ingest.Registry, as: Formats
  alias Pluteus.Ingest.Streams
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Orientation
  alias Pluteus.Presentation.Registry
  alias Pluteus.Presentation.Text
  alias Pluteus.Presentation.Tiles
  alias Pluteus.Presentation.Waveform
  alias Pluteus.Storage

  # ffmpeg takes a thread per core by default. The queue that runs generation already
  # bounds how many of these happen at once, and a derivative of one still image has no
  # use for the whole machine.
  @threads ~w(-threads 2)

  # A page of a comic at 600dpi is a few megabytes; past this the entry is not a page.
  # Read into memory because what is done with it is to write it straight back out, and
  # the archive reader's own ceiling is what refuses an entry that lied about its size.
  @page_ceiling 64 * 1_024 * 1_024

  @doc """
  Generates one artefact, or records why it could not.

  An unknown profile, a subject with no master, or a profile that does not apply to
  the subject are all refusals rather than failures: nothing was asked for that could
  have been made.
  """
  @spec run(Ecto.UUID.t(), String.t(), non_neg_integer()) ::
          {:ok, Presentation.Asset.t()}
          | {:refused, atom()}
          | {:error, String.t(), map()}
  def run(subject_id, profile, ordinal \\ 0) do
    with {:ok, declared} <- declared(profile),
         true <- Presentation.applies?(declared, subject_id),
         %Asset{} = source <- Presentation.source_for(subject_id) do
      generate(subject_id, declared, source, ordinal)
    else
      :error -> {:refused, :unknown_profile}
      false -> {:refused, :profile_does_not_apply}
      nil -> {:refused, :no_master}
    end
  end

  defp declared(profile), do: Registry.profile(profile)

  # The family is read off what the profile declares about itself rather than from its
  # name, so a registry that renames a profile does not need this to change. A waveform
  # states a point count or a rate, a key frame states where to take it, a sheet states
  # its tiling, and an image states only a width.
  defp generate(subject_id, %{"points" => _} = declared, source, _ordinal),
    do: waveform(subject_id, declared, source)

  defp generate(subject_id, %{"points_per_second" => _} = declared, source, _ordinal),
    do: waveform(subject_id, declared, source)

  defp generate(subject_id, %{"tile_columns" => _} = declared, source, _ordinal),
    do: trickplay(subject_id, declared, source)

  defp generate(subject_id, %{"tile_size" => _} = declared, source, _ordinal),
    do: pyramid(subject_id, declared, source)

  defp generate(subject_id, %{"proportion" => _} = declared, source, _ordinal),
    do: key_frame(subject_id, declared, source)

  # The one family a page may be asked for: a graded width of page *n*. The others are
  # of the holding and have no page, so an ordinal reaches them and they ignore it.
  defp generate(subject_id, %{"width" => _} = declared, source, ordinal),
    do: image(subject_id, declared, source, ordinal)

  defp generate(subject_id, %{"name" => "text-extracted"} = declared, source, _ordinal),
    do: text(subject_id, declared, source, :extracted)

  defp generate(subject_id, %{"name" => "text-word-positions"} = declared, source, _ordinal),
    do: text(subject_id, declared, source, :word_positions)

  defp generate(subject_id, %{"name" => "text-position-list"} = declared, source, _ordinal),
    do: text(subject_id, declared, source, :position_list)

  defp generate(_subject_id, _declared, _source, _ordinal), do: {:refused, :no_generator}

  defp image(subject_id, declared, %Asset{} = source, ordinal) do
    profile = Map.fetch!(declared, "name")
    extension = extension(Map.fetch!(declared, "format"))
    location = Presentation.location_for(subject_id, profile, ordinal, extension)

    case shown(subject_id, source, ordinal) do
      {:ok, from, scratch?} ->
        made = made(subject_id, declared, source, location, from, ordinal)
        if scratch?, do: Storage.delete(from)
        made

      {:error, kind, detail} ->
        failed(subject_id, profile, location, kind, detail)
    end
  end

  defp made(subject_id, declared, source, location, from, ordinal) do
    profile = Map.fetch!(declared, "name")
    orientation = from |> Storage.leading(Orientation.head_bytes()) |> Orientation.of()

    with :ok <- encode(from, location, declared),
         {:ok, measured} <- measure(location),
         {:ok, dimensions} <- dimensions_of(location),
         :ok <- turned(from, dimensions, orientation) do
      {width, height} = dimensions

      record(subject_id, declared, source, location, measured, %{
        width: width,
        height: height,
        ordinal: ordinal,
        descriptor: descriptor(declared, orientation)
      })
    else
      {:error, kind, detail} -> failed(subject_id, profile, location, kind, detail)
    end
  end

  # Which bytes this profile is made from. A holding carried by one file is that file,
  # whole; §12.1's page reader asks for page *n* of a container of pages, and then the
  # bytes are an entry of it. The ordinal is the page, which is also what identifies the
  # artefact (§11.6), so one archive yields one image profile per page rather than one.
  defp shown(subject_id, %Asset{format: format} = source, ordinal) do
    case {Formats.archive_format(format), ordinal} do
      {nil, 0} -> {:ok, source.location, false}
      {nil, page} -> {:error, "holding_has_no_pages", %{page: page}}
      {_archive, page} -> page(subject_id, source, page)
    end
  end

  # The entry is put where a derivative goes, used, and removed: it is a step in making
  # one rather than an artefact anybody asks for, and `presentation/` is the prefix
  # `Pluteus.Ingest.find_stray_bytes/1` does not walk.
  defp page(subject_id, source, ordinal) do
    case Container.read(source.location) do
      {:ok, %{content: content}} ->
        taken(subject_id, source, Enum.at(content, ordinal), ordinal, length(content))

      {:error, refusal} ->
        {:error, "archive_unreadable", %{refusal: inspect(refusal)}}
    end
  end

  defp taken(_subject_id, _source, nil, ordinal, pages),
    do: {:error, "page_not_held", %{page: ordinal, pages: pages}}

  defp taken(subject_id, source, entry, ordinal, _pages) do
    case Archive.read(source.location, entry, @page_ceiling) do
      {:ok, bytes} ->
        at = Presentation.location_for(subject_id, "page", ordinal, extension_of(entry))
        Storage.put(at, bytes)

        {:ok, at, true}

      {:error, refusal} ->
        {:error, "page_unreadable", %{entry: entry, refusal: inspect(refusal)}}
    end
  end

  defp extension_of(entry), do: entry |> Path.extname() |> String.trim_leading(".")

  # §11.2. Past §20's threshold a graded profile either throws away what the scan was
  # made for or sends the whole thing to look at one corner, so the pyramid is built
  # instead. Below the threshold it is refused: a profile set is smaller and simpler
  # there, and §11.2 says so.
  defp pyramid(subject_id, declared, %Asset{} = source) do
    profile = Map.fetch!(declared, "name")
    location = Presentation.location_for(subject_id, profile, 0, "zip")

    with {:ok, {width, height}} <- dimensions_of(source.location),
         true <- Tiles.tiled?(width, height),
         :ok <- Tiles.build(source.location, location),
         {:ok, measured} <- measure(location) do
      record(subject_id, declared, source, location, measured, %{
        width: width,
        height: height,
        descriptor: %{
          "tile_size" => Map.fetch!(declared, "tile_size"),
          "compliance_level" => Map.fetch!(declared, "compliance_level"),
          "extra_features" => Map.fetch!(declared, "extra_features"),
          "width" => width,
          "height" => height
        }
      })
    else
      false -> {:refused, :below_the_tiling_threshold}
      {:error, kind, detail} -> failed(subject_id, profile, location, kind, detail)
    end
  end

  # §11.5. Each of the three is one reading of the publication, written in the form
  # the registry states: the text as text, the other two as JSON. Every artefact records
  # which reader produced it, because text read out of a file and text guessed from
  # pixels are not equally reliable and a transcript nobody can tell was guessed is
  # worse than one labelled as guessed.
  defp text(subject_id, declared, %Asset{} = source, artefact) do
    profile = Map.fetch!(declared, "name")
    extension = if artefact == :extracted, do: "txt", else: "json"
    location = Presentation.location_for(subject_id, profile, 0, extension)
    class = Presentation.classification(subject_id) |> elem(0)

    with {:ok, read} <- read_text(source.location, class, artefact),
         :ok <- write(location, serialize(artefact, read)),
         {:ok, measured} <- measure(location) do
      record(subject_id, declared, source, location, measured, %{
        width: nil,
        height: nil,
        descriptor: text_descriptor(artefact, read)
      })
    else
      {:error, kind, detail} -> failed(subject_id, profile, location, kind, detail)
    end
  end

  defp read_text(location, class, :extracted), do: Text.extracted(location, class)
  defp read_text(location, class, :word_positions), do: Text.word_positions(location, class)
  defp read_text(location, class, :position_list), do: Text.position_list(location, class)

  defp serialize(:extracted, %{text: text}), do: text
  defp serialize(:word_positions, %{words: words}), do: Jason.encode!(%{"words" => words})
  defp serialize(:position_list, index), do: Jason.encode!(index)

  defp text_descriptor(:extracted, %{text: text, source: source}),
    do: %{"source" => source, "characters" => String.length(text)}

  defp text_descriptor(:word_positions, %{words: words, source: source}),
    do: %{"source" => source, "words" => length(words), "units" => "percent"}

  defp text_descriptor(:position_list, index), do: index

  # §11.4. The peaks are written as JSON with the resolution beside them, because the
  # numbers alone do not say how finely they were measured and criterion 30 turns on
  # exactly that.
  defp waveform(subject_id, declared, %Asset{} = source) do
    profile = Map.fetch!(declared, "name")
    location = Presentation.location_for(subject_id, profile, 0, "json")
    duration_ms = duration_of(source.location)

    points = Waveform.points(declared, duration_ms)

    with {:ok, peaks} <- Waveform.peaks(source.location, points, sample_rate(declared)),
         descriptor = waveform_descriptor(declared, duration_ms, peaks),
         :ok <- write(location, Jason.encode!(%{"resolution" => descriptor, "peaks" => peaks})),
         {:ok, measured} <- measure(location) do
      record(subject_id, declared, source, location, measured, %{
        width: nil,
        height: nil,
        descriptor: descriptor
      })
    else
      {:error, kind, detail} -> failed(subject_id, profile, location, kind, detail)
    end
  end

  # §11.3. One still for the poster position and a link preview, taken at a proportion
  # of the duration bounded at both ends: a short clip does not take frame zero, and a
  # long film does not take a frame far enough in to spoil it.
  defp key_frame(subject_id, declared, %Asset{} = source) do
    profile = Map.fetch!(declared, "name")
    location = Presentation.location_for(subject_id, profile, 0, "jpg")
    at_ms = frame_position(declared, duration_of(source.location))

    with :ok <- still_at(source.location, location, declared, at_ms),
         {:ok, measured} <- measure(location),
         {:ok, {width, height}} <- dimensions_of(location) do
      record(subject_id, declared, source, location, measured, %{
        width: width,
        height: height,
        descriptor: %{
          "width" => Map.fetch!(declared, "width"),
          "taken_at_ms" => at_ms,
          "format" => Map.fetch!(declared, "format")
        }
      })
    else
      {:error, kind, detail} -> failed(subject_id, profile, location, kind, detail)
    end
  end

  # §11.3. Frames at a fixed interval, tiled, with the index a client needs to go from
  # a time to a tile and a rectangle within it. The frames are extracted once; the
  # index is what lets the same extraction serve the interface's scrubber and a
  # client's own packaging.
  defp trickplay(subject_id, declared, %Asset{} = source) do
    profile = Map.fetch!(declared, "name")
    location = Presentation.location_for(subject_id, profile, 0, "jpg")
    duration_ms = duration_of(source.location)
    interval_ms = Map.fetch!(declared, "frame_interval_ms")
    columns = Map.fetch!(declared, "tile_columns")
    rows = Map.fetch!(declared, "tile_rows")

    frames = div(duration_ms, interval_ms)

    # A recording shorter than one interval has no frames at that interval, and a sheet
    # of none is not a narrower sheet. It is refused rather than written empty or
    # written at an interval other than the one the index declares.
    with true <- frames > 0,
         :ok <- sheet(source.location, location, declared, frames),
         {:ok, measured} <- measure(location),
         {:ok, {width, height}} <- dimensions_of(location) do
      record(subject_id, declared, source, location, measured, %{
        width: width,
        height: height,
        descriptor: %{
          "frame_interval_ms" => interval_ms,
          "frame_width" => Map.fetch!(declared, "frame_width"),
          "tile_columns" => columns,
          "tile_rows" => rows,
          "frames" => min(frames, columns * rows),
          "format" => Map.fetch!(declared, "format")
        }
      })
    else
      false -> {:refused, :shorter_than_one_interval}
      {:error, kind, detail} -> failed(subject_id, profile, location, kind, detail)
    end
  end

  # The scale keeps the aspect ratio and never enlarges: a profile is a ceiling, so a
  # 200px original asked for at 2048 stays 200px rather than being stretched into a
  # larger file with no more detail in it. `iw` is the decoded width, which is already
  # the turned one where an orientation was applied.
  defp encode(source, location, declared) do
    target = Storage.path(location)
    File.mkdir_p!(Path.dirname(target))

    width = Map.fetch!(declared, "width")

    args =
      ~w(-loglevel error -nostdin -y -i) ++
        [Storage.path(source)] ++
        ["-vf", "scale=w=min(#{width}\\,iw):h=-2"] ++
        ["-frames:v", "1", "-update", "1", "-map_metadata", "-1"] ++
        @threads ++
        quality(declared) ++
        [target]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, "derivative_not_generated", %{status: status, output: output}}
    end
  end

  # Where the source states a quarter turn, the derivative's long axis must be the
  # other one. A square source says nothing either way and is not checked.
  defp turned(source, dimensions, orientation) do
    if Orientation.turns?(orientation),
      do: exchanged(source, dimensions, orientation),
      else: :ok
  end

  defp exchanged(source, {width, height}, orientation) do
    case stored_dimensions(source) do
      nil -> :ok
      {same, same} -> :ok
      stored -> compare(stored, {width, height}, orientation)
    end
  end

  defp compare({stored_width, stored_height}, {width, height}, orientation) do
    if landscape?(width, height) == landscape?(stored_width, stored_height) do
      {:error, "orientation_not_applied",
       %{
         orientation: orientation,
         stored: "#{stored_width}x#{stored_height}",
         derivative: "#{width}x#{height}"
       }}
    else
      :ok
    end
  end

  # A probe reports the dimensions as stored, before any orientation is applied,
  # which is what makes it the thing to compare the derivative against.
  defp stored_dimensions(location) do
    case Probe.probe(location) do
      {:ok, probe} -> Streams.dimensions(probe)
      {:error, _unprobeable} -> nil
    end
  end

  defp landscape?(width, height), do: width > height

  defp quality(%{"quality" => quality}) when is_integer(quality) do
    # ffmpeg's mjpeg scale runs 2 (best) to 31 (worst), where the registry states a
    # percentage. A profile asking for 82 is asking for most of the quality and much
    # less of the size.
    ["-q:v", Integer.to_string(round(2 + (100 - quality) / 100 * 29))]
  end

  defp quality(_stating_none), do: []

  defp measure(location) do
    case Catalog.measure(location) do
      {:ok, measured} -> {:ok, measured}
      {:error, reason} -> {:error, "derivative_unreadable", %{reason: inspect(reason)}}
    end
  end

  defp dimensions_of(location) do
    case Probe.probe(location) do
      {:ok, probe} ->
        case Streams.dimensions(probe) do
          nil -> {:error, "derivative_has_no_geometry", %{location: location}}
          dimensions -> {:ok, dimensions}
        end

      {:error, reason} ->
        {:error, "derivative_unprobeable", %{reason: inspect(reason)}}
    end
  end

  # What the artefact declares about itself, which criterion 30 reads for a waveform
  # and a surface reads here to know it is not being offered more than was made.
  defp descriptor(declared, orientation) do
    %{
      "width" => Map.fetch!(declared, "width"),
      "format" => Map.fetch!(declared, "format"),
      "orientation_applied" => orientation || 1
    }
  end

  defp extension("jpeg"), do: "jpg"
  defp extension("webp"), do: "webp"
  defp extension("png"), do: "png"

  defp media_type(%{"media_type" => media_type}), do: media_type
  defp media_type(%{"format" => format}), do: image_media_type(format)

  defp image_media_type("jpeg"), do: "image/jpeg"
  defp image_media_type("webp"), do: "image/webp"
  defp image_media_type("png"), do: "image/png"

  # The one place a row is written, so every family records the same things about
  # itself and the source it came from.
  defp record(subject_id, declared, %Asset{} = source, location, measured, own) do
    Presentation.record(%{
      subject_id: subject_id,
      profile: Map.fetch!(declared, "name"),
      ordinal: Map.get(own, :ordinal, 0),
      location: location,
      media_type: media_type(declared),
      size: measured.size,
      digest: measured.digest,
      digest_algorithm: measured.digest_algorithm,
      width: own.width,
      height: own.height,
      descriptor: own.descriptor,
      source_asset_id: source.id,
      source_digest: source.digest,
      generated_at: DateTime.utc_now(),
      last_served_at: DateTime.utc_now()
    })
  end

  defp failed(subject_id, profile, location, kind, detail) do
    _ = Storage.delete(location)

    Ingest.record_finding(%{
      stage: :normalize,
      kind: kind,
      permanent: false,
      detail: Map.merge(detail, %{subject: subject_id, profile: profile}),
      input_id: subject_id
    })

    {:error, kind, detail}
  end

  defp write(location, bytes) do
    target = Storage.path(location)
    File.mkdir_p!(Path.dirname(target))

    case File.write(target, bytes) do
      :ok -> :ok
      {:error, reason} -> {:error, "derivative_not_written", %{reason: inspect(reason)}}
    end
  end

  # A recording whose container states no duration cannot be measured along, and
  # §11.4's point count and §11.3's interval are both measured along it.
  defp duration_of(location) do
    case Probe.probe(location) do
      {:ok, probe} ->
        case get_in(probe, ["format", "duration"]) do
          nil -> 0
          _stated -> Streams.duration_ms(probe)
        end

      {:error, _unprobeable} ->
        0
    end
  end

  defp sample_rate(declared), do: Map.fetch!(declared, "sample_rate")

  defp waveform_descriptor(declared, duration_ms, peaks) do
    declared
    |> Map.take(["points", "points_per_second", "bits", "channels"])
    |> Map.merge(%{"duration_ms" => duration_ms, "points_measured" => length(peaks)})
  end

  # §20's proportion, bounded at both ends.
  defp frame_position(declared, duration_ms) do
    proportion = Map.fetch!(declared, "proportion")
    minimum = Map.fetch!(declared, "minimum_ms")
    maximum = Map.fetch!(declared, "maximum_ms")

    duration_ms
    |> Kernel.*(proportion)
    |> round()
    |> max(0)
    |> min(maximum)
    |> then(fn at ->
      if duration_ms > minimum, do: max(at, min(minimum, duration_ms)), else: 0
    end)
  end

  defp still_at(source, location, declared, at_ms) do
    target = Storage.path(location)
    File.mkdir_p!(Path.dirname(target))

    width = Map.fetch!(declared, "width")

    args =
      ~w(-loglevel error -nostdin -y -ss) ++
        [format_seconds(at_ms), "-i", Storage.path(source)] ++
        ["-vf", "scale=w=min(#{width}\\,iw):h=-2", "-frames:v", "1", "-update", "1"] ++
        ["-map_metadata", "-1"] ++ @threads ++ [target]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, "key_frame_not_taken", %{status: status, output: output}}
    end
  end

  defp sheet(source, location, declared, frames) do
    target = Storage.path(location)
    File.mkdir_p!(Path.dirname(target))

    interval_ms = Map.fetch!(declared, "frame_interval_ms")
    width = Map.fetch!(declared, "frame_width")
    columns = Map.fetch!(declared, "tile_columns")
    rows = Map.fetch!(declared, "tile_rows")

    chain =
      "fps=1/#{interval_ms / 1000}," <>
        "scale=w=#{width}:h=-2," <>
        "tile=#{columns}x#{rows}"

    args =
      ~w(-loglevel error -nostdin -y -i) ++
        [Storage.path(source)] ++
        ["-vf", chain, "-frames:v", "1", "-update", "1", "-map_metadata", "-1"] ++
        @threads ++ [target]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, status} ->
        {:error, "trickplay_not_tiled", %{status: status, output: output, frames: frames}}
    end
  end

  defp format_seconds(milliseconds), do: :erlang.float_to_binary(milliseconds / 1000, decimals: 3)
end
