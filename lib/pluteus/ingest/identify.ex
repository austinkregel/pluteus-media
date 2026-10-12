defmodule Pluteus.Ingest.Identify do
  @moduledoc """
  Decides what stored bytes are, from the bytes and nothing else (spec-04 §5).

  The file's name is consulted once, and only to recognize a companion, which is
  decided before anything else so that album art never reaches placement as a
  photograph, nor lyrics as a document (§4.6). Where a name alone cannot say
  what a companion is, the file's first bytes decide: an `.nfo` holding markup
  is a media manager's metadata, and one holding a release's notes is a
  description.

  A container is read for what it holds, and a metadata document the registry names inside
  one is read here as an embedded tag (§6.9 criterion 35). It describes the container
  rather than being content of it, so it is neither a companion nor a page, and a document
  the registry does not name is content.

  Essence is decided per content stream. Embedded cover art, data streams,
  timecode tracks and attachments accompany the media and are not counted, so
  an MP3 carrying a JPEG of its sleeve is as lossy as its audio and no more.
  """

  alias Pluteus.Formats
  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Ingest.Container
  alias Pluteus.Ingest.Probe
  alias Pluteus.Ingest.Registry
  alias Pluteus.Storage

  @content_types ~w(audio video subtitle)

  # Enough of a file to hold an XML declaration, a doctype and the element that
  # follows them.
  @head_bytes 4_096

  @doc """
  Everything identification records about an acquisition's stored bytes, or
  why it cannot.

  An error is permanent: the same bytes give the same answer on every attempt.
  """
  @spec identify(Acquisition.t()) :: {:ok, map()} | {:error, {String.t(), map()}}
  def identify(%Acquisition{} = acquisition),
    do: identify(acquisition, Storage.path(acquisition.location))

  @doc """
  The same, of a file read where it lies rather than at its location.

  §4.3 moves a file out of the inbox once the deployment takes it, and what it is has to
  be known before that: a file nothing can say the category of is one the household still
  has to deal with, and it deals with it where it put it (§6.3).
  """
  @spec identify(Acquisition.t(), Path.t()) :: {:ok, map()} | {:error, {String.t(), map()}}
  def identify(%Acquisition{} = acquisition, path) do
    companion_kind =
      Registry.companion_kind(
        Path.basename(acquisition.inbox_path),
        fn -> Storage.leading_file(path, @head_bytes) end
      )

    with {:ok, format} <- format(path),
         {:ok, probe} <- probe(path, format, companion_kind) do
      streams = streams(probe)

      with {:ok, media_class, container_tags} <-
             media_class(companion_kind, streams, probe, format, path) do
        {:ok,
         %{
           format: format,
           probe: probe,
           streams: streams,
           essence: essence(streams, probe, format),
           media_class: media_class,
           companion_kind: companion_kind,
           container_tags: container_tags
         }}
      end
    end
  end

  # §5.1. PRONOM answers first; a deployment signature answers what it leaves
  # unknown, from the content at a stated offset.
  defp format(path) do
    case Formats.identify_file(path) do
      {:ok, format} ->
        if format == Formats.unknown(), do: {:ok, by_signature(path)}, else: {:ok, format}

      {:error, reason} ->
        {:error, {"format_unidentifiable", %{reason: inspect(reason)}}}
    end
  end

  defp by_signature(path) do
    path
    |> Storage.leading_file(Registry.signature_span())
    |> Registry.byte_signature()
    |> case do
      nil -> Formats.unknown()
      format -> format
    end
  end

  # A document or plain text file is not a container, and ffprobe says so by
  # failing. That is the expected answer for a format the registry knows carries
  # no streams. For anything else a failure means the bytes do not decode.
  defp probe(path, format, companion_kind) do
    case Probe.probe_file(path) do
      {:ok, probe} ->
        {:ok, probe}

      {:error, {:ffprobe, status, output}} ->
        # A format the registry knows carries no streams has nothing for ffprobe to read,
        # and an archive is one of those: what it holds is read from its entries instead.
        #
        # A companion is the same case for a different reason: §4.6 decided what it is
        # from its name and its first bytes, and a lyrics file or a media manager's
        # document is not a thing ffprobe reads. It is still probed, because a cover's
        # dimensions are read from the same answer, but failing to read one is not a
        # failure to know what it is.
        if companion_kind || Registry.streamless_format(format) ||
             Registry.archive_format(format),
           do: {:ok, nil},
           else: {:error, {"undecodable", %{format: format, status: status, output: output}}}
    end
  end

  @doc """
  One summary per probed stream: what it is, what distinguishes it from its
  siblings, whether it carries content, and its essence if it does.
  """
  @spec streams(map() | nil) :: [map()]
  def streams(nil), do: []

  def streams(%{} = probe) do
    probe
    |> Map.get("streams", [])
    |> Enum.map(fn stream ->
      content = content?(stream)

      %{
        "kind" => stream["codec_type"],
        "codec" => stream["codec_name"],
        "language" => language(stream),
        "disposition" => disposition(stream),
        "channels" => stream["channels"],
        "channel_layout" => stream["channel_layout"],
        "content" => content,
        "essence" => if(content, do: Atom.to_string(Registry.stream_essence(stream)))
      }
    end)
  end

  defp content?(stream) do
    stream["codec_type"] in @content_types and
      get_in(stream, ["disposition", "attached_pic"]) != 1
  end

  # "und" is ISO 639-2's code for a language not determined, which is a missing
  # language and is recorded as one.
  defp language(stream) do
    case get_in(stream, ["tags", "language"]) do
      nil -> nil
      "und" -> nil
      language -> language
    end
  end

  defp disposition(stream) do
    stream
    |> Map.get("disposition", %{})
    |> Enum.filter(fn {_flag, set} -> set == 1 end)
    |> Enum.map(fn {flag, _set} -> flag end)
    |> Enum.sort()
  end

  @doc """
  The file's essence from its content streams, or from its format where the
  probe found no streams at all (§5.2).
  """
  @spec essence([map()], map() | nil, String.t()) :: atom()
  def essence([], _probe, format) do
    case Registry.streamless_format(format) do
      %{essence: essence} -> essence
      nil -> :unknown
    end
  end

  def essence(streams, _probe, _format) do
    essences = for %{"content" => true, "essence" => essence} <- streams, do: essence

    cond do
      essences == [] -> :not_applicable
      "lossy" in essences -> :lossy
      Enum.all?(essences, &(&1 == "lossless")) -> :lossless
      true -> :unknown
    end
  end

  defp media_class(kind, _streams, _probe, _format, _path) when is_binary(kind),
    do: {:ok, :companion, %{}}

  defp media_class(nil, streams, probe, format, path) do
    kinds = for %{"content" => true, "kind" => kind} <- streams, do: kind

    cond do
      "video" in kinds ->
        {:ok,
         if(Registry.image_container?(probe["format"]["format_name"]), do: :image, else: :video),
         %{}}

      "audio" in kinds ->
        {:ok, :audio, %{}}

      "subtitle" in kinds ->
        {:ok, :text, %{}}

      true ->
        streamless_class(streams, format, path)
    end
  end

  defp streamless_class(streams, format, path) do
    case {Registry.streamless_format(format), Registry.archive_format(format)} do
      {%{class: class}, _archive} when streams == [] ->
        {:ok, class, %{}}

      {nil, %{class: class}} when streams == [] ->
        corroborated(class, format, path)

      _unclassified ->
        {:error, {"unclassifiable", %{format: format, streams: length(streams)}}}
    end
  end

  # §5.3. An archive's format is any ZIP or any RAR, so the class is taken only where every
  # entry of content is one a surface could render. An entry outside that names itself: a
  # ZIP of holiday photographs becomes a comic issue a member corrects, but a ZIP holding
  # an installer is not a holding this deployment knows how to be wrong about.
  #
  # §6.9 criterion 35. A metadata document the registry names is not content and is read
  # here instead, as the embedded tags §6.3 weighs. An unnamed document is content, so an
  # XML that names nothing the registry knows is weighed as a page would be and refused.
  defp corroborated(class, format, path) do
    case Container.read_file(path) do
      {:ok, %{content: [], documents: []}} ->
        {:error, {"archive_is_empty", %{format: format}}}

      {:ok, %{content: [], documents: documents}} ->
        {:error, {"archive_holds_no_content", %{format: format, documents: documents}}}

      {:ok, %{content: content, tags: tags}} ->
        case Enum.reject(content, &Registry.renderable_entry?/1) do
          [] -> {:ok, class, tags}
          unreadable -> {:error, {"unclassifiable", %{format: format, entries: unreadable}}}
        end

      {:error, refusal} ->
        {:error, refused(format, refusal)}
    end
  end

  defp refused(format, {:too_many, ceiling}),
    do: {"archive_holds_too_much", %{format: format, ceiling: ceiling}}

  defp refused(format, {:too_long, ceiling}),
    do: {"archive_holds_too_much", %{format: format, ceiling: ceiling}}

  defp refused(format, {:timed_out, milliseconds}),
    do: {"archive_unreadable", %{format: format, timed_out_after_ms: milliseconds}}

  defp refused(format, {:unreadable, status, output}),
    do: {"archive_unreadable", %{format: format, status: status, output: output}}

  defp refused(format, {:document_unreadable, entry, reason}),
    do:
      {"container_document_unreadable",
       %{format: format, entry: entry, reason: inspect(reason) |> String.slice(0, 500)}}
end
