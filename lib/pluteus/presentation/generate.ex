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

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Asset
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Probe
  alias Pluteus.Ingest.Streams
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Orientation
  alias Pluteus.Presentation.Registry
  alias Pluteus.Storage

  @doc """
  Generates one artefact, or records why it could not.

  An unknown profile, a subject with no master, or a profile that does not apply to
  the subject are all refusals rather than failures: nothing was asked for that could
  have been made.
  """
  @spec run(Ecto.UUID.t(), String.t()) ::
          {:ok, Presentation.Asset.t()}
          | {:refused, atom()}
          | {:error, String.t(), map()}
  def run(subject_id, profile) do
    with {:ok, declared} <- declared(profile),
         true <- Presentation.applies?(declared, subject_id),
         %Asset{} = source <- Presentation.source_for(subject_id) do
      generate(subject_id, declared, source)
    else
      :error -> {:refused, :unknown_profile}
      false -> {:refused, :profile_does_not_apply}
      nil -> {:refused, :no_master}
    end
  end

  defp declared(profile), do: Registry.profile(profile)

  # Only the image family is made here. The others are named by §20 and their
  # generators are separate pieces of work; asking for one answers plainly rather
  # than writing an image under its name.
  defp generate(subject_id, %{"width" => _} = declared, source),
    do: image(subject_id, declared, source)

  defp generate(_subject_id, _declared, _source), do: {:refused, :no_generator}

  defp image(subject_id, declared, %Asset{} = source) do
    profile = Map.fetch!(declared, "name")
    extension = extension(Map.fetch!(declared, "format"))
    location = Presentation.location_for(subject_id, profile, 0, extension)

    orientation =
      source.location
      |> Storage.leading(Orientation.head_bytes())
      |> Orientation.of()

    with :ok <- encode(source.location, location, declared),
         {:ok, measured} <- measure(location),
         {:ok, dimensions} <- dimensions_of(location),
         :ok <- turned(source.location, dimensions, orientation) do
      {width, height} = dimensions

      Presentation.record(%{
        subject_id: subject_id,
        profile: profile,
        ordinal: 0,
        location: location,
        media_type: media_type(Map.fetch!(declared, "format")),
        size: measured.size,
        digest: measured.digest,
        digest_algorithm: measured.digest_algorithm,
        width: width,
        height: height,
        descriptor: descriptor(declared, orientation),
        source_asset_id: source.id,
        source_digest: source.digest,
        generated_at: DateTime.utc_now(),
        last_served_at: DateTime.utc_now()
      })
    else
      {:error, kind, detail} ->
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

  defp media_type("jpeg"), do: "image/jpeg"
  defp media_type("webp"), do: "image/webp"
  defp media_type("png"), do: "image/png"
end
