defmodule Pluteus.Ingest.Streams do
  @moduledoc """
  Reading placement evidence out of probe output: embedded tags, positions,
  durations, and the identity of each stream in a container.
  """

  @key {__MODULE__, :ffprobe_version}

  # A player's preference among streams, which muxers rewrite freely. It is not
  # part of what a stream is, so it does not name one.
  @unstable_dispositions ["default"]

  @doc """
  A file's embedded tags, with keys lowercased: the container's, and those of
  its first audio stream, where Ogg and Opus keep them. The container's win
  where both carry a key.

  Keys and values are in Unicode normal form C. Taggers differ in whether
  "é" is one code point or "e" and a combining accent, and two files naming
  one album must compare equal whichever wrote them.
  """
  @spec tags(map() | nil) :: map()
  def tags(nil), do: %{}

  def tags(probe) do
    stream_tags =
      probe
      |> Map.get("streams", [])
      |> Enum.find(%{}, &(&1["codec_type"] == "audio"))
      |> Map.get("tags", %{})

    stream_tags
    |> Map.merge(get_in(probe, ["format", "tags"]) || %{})
    |> Map.new(fn {key, value} ->
      {key |> String.downcase() |> String.normalize(:nfc), String.normalize(value, :nfc)}
    end)
  end

  @doc """
  The first of several tag keys a file carries a value for.
  """
  @spec first(map(), [String.t()]) :: String.t() | nil
  def first(tags, keys), do: Enum.find_value(keys, &tags[&1])

  @doc """
  A position from a tag such as `3` or `3/12`. A value that is not a number,
  such as a vinyl side's `A1`, gives no position.
  """
  @spec number(map(), [String.t()]) :: pos_integer() | nil
  def number(tags, keys) do
    with value when is_binary(value) <- first(tags, keys),
         {number, _rest} when number > 0 <- value |> String.trim() |> Integer.parse() do
      number
    else
      _no_position -> nil
    end
  end

  @doc """
  The number of discs in the release, from a total tag or from `n/m`.
  """
  @spec disc_total(map()) :: pos_integer() | nil
  def disc_total(tags) do
    case first(tags, ["disctotal", "totaldiscs"]) do
      nil -> total_of(first(tags, ["disc", "discnumber"]))
      total -> number(%{"total" => total}, ["total"])
    end
  end

  defp total_of(nil), do: nil

  defp total_of(disc) do
    case String.split(disc, "/") do
      [_disc, total] -> number(%{"total" => total}, ["total"])
      _no_total -> nil
    end
  end

  @doc """
  The MusicBrainz release identifiers a file carries, distinct. Taggers write
  them under different keys, and ffprobe joins repeated values with `;`, so a
  file tagged twice can carry two.
  """
  @spec release_identifiers(map()) :: [String.t()]
  def release_identifiers(tags) do
    ["musicbrainz_albumid", "musicbrainz album id"]
    |> Enum.flat_map(&String.split(tags[&1] || "", ";"))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  @doc """
  The pixel dimensions of a file's first visual stream, or nil where it has none.

  A still image is one video stream to a probe, so this answers a photograph and a
  film alike. Cover art embedded beside audio is an attached picture and is passed
  over: its dimensions are the artwork's, not the holding's ([spec-10] §11.2).
  """
  @spec dimensions(map() | nil) :: {pos_integer(), pos_integer()} | nil
  def dimensions(nil), do: nil

  def dimensions(probe) do
    probe
    |> Map.get("streams", [])
    |> Enum.find(fn stream ->
      stream["codec_type"] == "video" and get_in(stream, ["disposition", "attached_pic"]) != 1
    end)
    |> case do
      %{"width" => width, "height" => height}
      when is_integer(width) and is_integer(height) and width > 0 and height > 0 ->
        {width, height}

      _no_visual_stream ->
        nil
    end
  end

  @doc """
  The container's duration in milliseconds.
  """
  @spec duration_ms(map()) :: non_neg_integer()
  def duration_ms(probe) do
    {seconds, ""} = probe |> get_in(["format", "duration"]) |> Float.parse()
    round(seconds * 1000)
  end

  @doc """
  The `track` selector for each content stream (spec-01 §8.5): kind, language,
  the dispositions that say what the stream is, channel count, and an ordinal
  among streams alike in all four. Neither index nor codec enters into it, so
  the same stream is named the same way after normalization reorders or
  re-encodes the container.
  """
  @spec track_selectors([map()]) :: [map()]
  def track_selectors(content_streams) do
    content_streams
    |> Enum.map_reduce(%{}, fn stream, seen ->
      identity = {
        stream["kind"],
        stream["language"],
        stream["disposition"] -- @unstable_dispositions,
        stream["channels"]
      }

      ordinal = Map.get(seen, identity, 0) + 1
      {{identity, ordinal}, Map.put(seen, identity, ordinal)}
    end)
    |> elem(0)
    |> Enum.map(fn {{kind, language, disposition, channels}, ordinal} ->
      %{
        selector_type: :track,
        stream_kind: String.to_existing_atom(kind),
        stream_language: language,
        stream_disposition: disposition,
        stream_channels: channels,
        stream_ordinal: ordinal
      }
    end)
  end

  @doc """
  The version of the ffprobe build, which names the probing tool's derivations.
  """
  @spec ffprobe_version() :: String.t()
  def ffprobe_version do
    case :persistent_term.get(@key, nil) do
      nil ->
        {output, 0} = System.cmd("ffprobe", ["-version"])

        ["ffprobe", "version", version | _] =
          output |> String.split("\n") |> hd() |> String.split(" ")

        :persistent_term.put(@key, version)
        version

      version ->
        version
    end
  end
end
