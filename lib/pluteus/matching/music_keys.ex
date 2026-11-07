defmodule Pluteus.Matching.MusicKeys do
  @moduledoc """
  The identifiers a piece of music carries (spec-05 §9.1): MusicBrainz identifiers and
  ISRCs in its tags, the recording identifier and ISRC an MP3 keeps in ID3 frames ffprobe
  does not report, and the disc ID a cue sheet's table of contents hashes to.

  Every one is an equality (§4.2): a value the holding carries, or computed from it by a
  rule that admits no near miss. Where the registry records it, each is read to the form
  its scheme defines and checked against it before it is used as a key (§4.4).

  **What cannot be keyed is said, and never quietly dropped.** A value not of its
  scheme's form is a finding (criterion 12). So is a scheme that allows one identifier at
  a level carrying two different ones (§5.4, criterion 23): the evidence is contradictory,
  and neither value is written. A tag that is there and unreadable is a finding too.
  """

  alias Pluteus.DiscId
  alias Pluteus.Id3
  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Ingest.Cue
  alias Pluteus.Ingest.Place
  alias Pluteus.Matching.Registry
  alias Pluteus.Storage

  @corpus "musicbrainz"

  @typedoc "Why a holding's identifiers cannot be keyed, as a finding's kind and detail."
  @type unkeyable :: {String.t(), map()}

  @doc """
  The identifiers a holding's own tags and frames carry, by scheme, each scheme's values
  distinct and in the form its scheme defines. A scheme it carries nothing for is absent.
  """
  @spec carried(Acquisition.t(), String.t()) ::
          {:ok, %{String.t() => [String.t()]}} | {:error, unkeyable()}
  def carried(%Acquisition{} = acquisition, location) do
    keys = Registry.keys!(@corpus)
    tags = Place.embedded_tags(acquisition)

    from_tags =
      Map.new(keys.tags, fn {scheme, tag_keys} ->
        {scheme, Enum.flat_map(tag_keys, &split(tags[&1]))}
      end)

    with {:ok, from_frames} <- frames(location, keys) do
      from_tags
      |> Map.merge(from_frames, fn _scheme, tagged, framed -> tagged ++ framed end)
      |> Enum.reject(fn {_scheme, values} -> values == [] end)
      |> Enum.reduce_while({:ok, %{}}, &formed_into/2)
    end
  end

  defp formed_into({scheme, values}, {:ok, carried}) do
    case formed(scheme, values) do
      {:ok, formed} -> {:cont, {:ok, Map.put(carried, scheme, formed)}}
      {:error, _unkeyable} = refused -> {:halt, refused}
    end
  end

  # ffprobe joins a tag written twice with `;`.
  defp split(nil), do: []
  defp split(value), do: value |> String.split(";") |> Enum.map(&String.trim/1)

  # An MP3's ID3 frames, read from the tag at the head of the file where it has one.
  defp frames(location, keys) do
    case Id3.tag_bytes(Storage.leading(location, 10)) do
      :none -> {:ok, %{}}
      {:error, unreadable} -> {:error, id3_unreadable(unreadable)}
      {:ok, length} -> location |> Storage.leading(length) |> Id3.frames() |> framed(keys)
    end
  end

  defp framed({:ok, frames}, keys) do
    with {:ok, recordings} <- Id3.unique_file_identifiers(frames, keys.ufid_owner),
         {:ok, texts} <- texts(frames, keys.id3_text) do
      {:ok, Map.merge(%{keys.ufid_scheme => recordings}, texts, fn _, a, b -> a ++ b end)}
    else
      {:error, unreadable} -> {:error, id3_unreadable(unreadable)}
    end
  end

  defp framed({:error, unreadable}, _keys), do: {:error, id3_unreadable(unreadable)}

  defp texts(frames, by_frame) do
    Enum.reduce_while(by_frame, {:ok, %{}}, fn {frame, scheme}, {:ok, texts} ->
      case Id3.text(frames, frame) do
        {:ok, values} -> {:cont, {:ok, Map.update(texts, scheme, values, &(&1 ++ values))}}
        {:error, _} = unreadable -> {:halt, unreadable}
      end
    end)
  end

  defp id3_unreadable(unreadable),
    do: {"tags_unreadable", %{"tag" => "id3v2", "unreadable" => inspect(unreadable)}}

  # Each value read to its scheme's form, then checked against it; and a scheme allowing
  # one identifier at its level holding one.
  defp formed(scheme, values) do
    syntax = Registry.syntax!(scheme)

    {formed, malformed} =
      values
      |> Enum.map(&{&1, form(syntax, &1)})
      |> Enum.split_with(fn {_value, formed} -> formed != :malformed end)

    distinct = formed |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    cond do
      malformed != [] ->
        {:error,
         {"identifier_malformed",
          %{"scheme" => scheme, "values" => Enum.map(malformed, &elem(&1, 0))}}}

      match?([_, _ | _], distinct) and not Registry.several?(scheme) ->
        {:error, {"identifiers_contradict", %{"scheme" => scheme, "values" => distinct}}}

      true ->
        {:ok, distinct}
    end
  end

  # A UUID's form is its lowercase hyphenated one. An ISRC is often displayed with hyphens
  # (ISO 3901's `CC-XXX-YY-NNNNN`), which are not part of it.
  defp form(:uuid, value) do
    case Ecto.UUID.cast(String.downcase(value)) do
      {:ok, uuid} -> uuid
      :error -> :malformed
    end
  end

  defp form(:isrc, value) do
    isrc = value |> String.replace(["-", " "], "") |> String.upcase()
    if isrc =~ ~r/^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$/, do: isrc, else: :malformed
  end

  defp form(:discid, value) do
    if value =~ ~r/^[A-Za-z0-9._]{27}-$/, do: value, else: :malformed
  end

  @typedoc "A disc's table of contents and the ID it hashes to, or why there is none."
  @type disc :: {:ok, %{toc: DiscId.toc(), discid: String.t()}} | {:not_computable, term()}

  @doc """
  The disc a file and the cue sheet describing it make, where the file is a CD's audio
  sample for sample and the sheet says enough for a table of contents (§9.1).

  A file whose length is not a whole number of sectors is not a CD's audio sample for
  sample, and is a finding: it says the rip is not what its cue sheet describes. Every
  other reason there is no table of contents is a bound of what a cue sheet states, and
  is answered as such.
  """
  @spec disc(Acquisition.t(), Cue.t()) :: disc() | {:error, unkeyable()}
  def disc(%Acquisition{probe: probe}, %{tracks: tracks}) do
    %{disc: wanted} = Registry.keys!(@corpus)

    with {:ok, samples} <- cd_samples(probe, wanted),
         {:ok, toc} <- toc(tracks, samples) do
      {:ok, %{toc: toc, discid: DiscId.id(toc)}}
    end
  end

  defp toc(tracks, samples) do
    case DiscId.toc(tracks, samples) do
      {:ok, toc} ->
        {:ok, toc}

      {:error, {:not_whole_sectors, remainder}} ->
        {:error, {"disc_not_whole_sectors", %{"samples" => samples, "remainder" => remainder}}}

      {:error, reason} ->
        {:not_computable, reason}
    end
  end

  # The file's length in samples, where its audio is what a CD holds.
  defp cd_samples(probe, wanted) do
    audio = probe |> Map.get("streams", []) |> Enum.find(&(&1["codec_type"] == "audio"))

    with %{} <- audio,
         true <- audio["codec_name"] in wanted.codecs,
         true <- audio["sample_rate"] == Integer.to_string(wanted.sample_rate),
         true <- audio["channels"] == wanted.channels,
         {:ok, samples} <- samples(audio, wanted.sample_rate) do
      {:ok, samples}
    else
      _not_a_cd -> {:not_computable, :not_cd_audio}
    end
  end

  # duration_ts counts the stream's time base; in samples, it is an exact number or the
  # length is not one the stream states.
  defp samples(%{"duration_ts" => ticks, "time_base" => time_base}, rate)
       when is_integer(ticks) or is_binary(ticks) do
    ticks = if is_binary(ticks), do: String.to_integer(ticks), else: ticks
    [numerator, denominator] = time_base |> String.split("/") |> Enum.map(&String.to_integer/1)
    scaled = ticks * numerator * rate

    if rem(scaled, denominator) == 0,
      do: {:ok, div(scaled, denominator)},
      else: :not_whole_samples
  end

  defp samples(_audio, _rate), do: :length_not_stated
end
