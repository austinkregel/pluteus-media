defmodule Pluteus.Ingest.Identify do
  @moduledoc """
  Decides what stored bytes are, from the bytes and nothing else (spec-04 §5).

  The file's name is consulted once, and only to recognize a companion, which is
  decided before anything else so that album art never reaches placement as a
  photograph, nor lyrics as a document (§4.6).

  Essence is decided per content stream. Embedded cover art, data streams,
  timecode tracks and attachments accompany the media and are not counted, so
  an MP3 carrying a JPEG of its sleeve is as lossy as its audio and no more.
  """

  alias Pluteus.Formats
  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Ingest.Probe
  alias Pluteus.Ingest.Registry

  @content_types ~w(audio video subtitle)

  @doc """
  Everything identification records about an acquisition's stored bytes, or
  why it cannot.

  An error is permanent: the same bytes give the same answer on every attempt.
  """
  @spec identify(Acquisition.t()) :: {:ok, map()} | {:error, {String.t(), map()}}
  def identify(%Acquisition{} = acquisition) do
    companion_kind = acquisition.inbox_path |> Path.basename() |> Registry.companion_kind()

    with {:ok, format} <- format(acquisition.location),
         {:ok, probe} <- probe(acquisition.location, format) do
      streams = streams(probe)

      with {:ok, media_class} <- media_class(companion_kind, streams, probe, format) do
        {:ok,
         %{
           format: format,
           probe: probe,
           streams: streams,
           essence: essence(streams, probe, format),
           media_class: media_class,
           companion_kind: companion_kind
         }}
      end
    end
  end

  defp format(location) do
    case Formats.identify(location) do
      {:ok, format} -> {:ok, format}
      {:error, reason} -> {:error, {"format_unidentifiable", %{reason: inspect(reason)}}}
    end
  end

  # A document or plain text file is not a container, and ffprobe says so by
  # failing. That is the expected answer for a format the registry knows carries
  # no streams. For anything else a failure means the bytes do not decode.
  defp probe(location, format) do
    case Probe.probe(location) do
      {:ok, probe} ->
        {:ok, probe}

      {:error, {:ffprobe, status, output}} ->
        if Registry.streamless_format(format),
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

  defp media_class(kind, _streams, _probe, _format) when is_binary(kind), do: {:ok, :companion}

  defp media_class(nil, streams, probe, format) do
    kinds = for %{"content" => true, "kind" => kind} <- streams, do: kind

    cond do
      "video" in kinds ->
        {:ok,
         if(Registry.image_container?(probe["format"]["format_name"]), do: :image, else: :video)}

      "audio" in kinds ->
        {:ok, :audio}

      "subtitle" in kinds ->
        {:ok, :text}

      true ->
        streamless_class(streams, format)
    end
  end

  defp streamless_class(streams, format) do
    case Registry.streamless_format(format) do
      %{class: class} when streams == [] ->
        {:ok, class}

      _unclassified ->
        {:error, {"unclassifiable", %{format: format, streams: length(streams)}}}
    end
  end
end
