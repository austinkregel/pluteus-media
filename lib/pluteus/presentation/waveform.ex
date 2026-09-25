defmodule Pluteus.Presentation.Waveform do
  @moduledoc """
  The shape of a recording, at a stated resolution ([spec-10] §11.4).

  Two artefacts with different scaling laws, which the spec forbids conflating. An
  **overview** is a fixed number of points however long the recording is, so it is a
  few kilobytes for a track and a few kilobytes for a nine-hour reading, and it is what
  a transport bar draws. A **detail** waveform's size scales with duration, and exists
  for inspecting a passage.

  **A waveform declares its own resolution, and nothing offers a zoom finer than it.**
  Decimating a stored waveform is correct — fewer points than were measured is a
  coarser view of the same shape. Interpolating one draws a shape the audio does not
  have, and a person looking for a click between two samples would find one that was
  invented by the drawing.

  A point is a peak, not a mean. Resampling to a low rate would average the samples
  away and flatten exactly the transients a waveform is looked at for, so the samples
  are decoded at a rate above the point rate and the largest magnitude in each bucket
  is kept.
  """

  alias Pluteus.Storage

  # Read the decoded stream in pieces. A nine-hour recording at the registry's rate is
  # hundreds of megabytes of samples, which is bucketed as it arrives rather than held.
  @chunk_bytes 1_048_576

  @doc """
  The peaks of a recording, one per point, each from 0 to 255.

  `points` is how many to answer, which the caller computes from the profile: a fixed
  count for an overview, and the duration times the point rate for a detail.
  """
  @spec peaks(String.t(), pos_integer(), pos_integer()) ::
          {:ok, [non_neg_integer()]} | {:error, String.t(), map()}
  def peaks(location, points, sample_rate) when points > 0 do
    decoded = Path.join(System.tmp_dir!(), "waveform-#{System.unique_integer([:positive])}.pcm")

    try do
      with :ok <- decode(location, decoded, sample_rate),
           {:ok, samples} <- sample_count(decoded) do
        {:ok, bucket(decoded, samples, points)}
      end
    after
      File.rm(decoded)
    end
  end

  @doc """
  How many points a profile asks for, given the recording's duration.

  An overview states its count. A detail states a rate, and a recording shorter than
  one point at that rate still gets one, because a waveform of nothing is not a
  narrower waveform.
  """
  @spec points(map(), non_neg_integer()) :: pos_integer()
  def points(%{"points" => points}, _duration_ms), do: points

  def points(%{"points_per_second" => rate}, duration_ms),
    do: max(round(duration_ms * rate / 1000), 1)

  @doc """
  The finest resolution an artefact supports, in points per second.

  This is what criterion 30 rests on: a surface compares the zoom it wants against
  this and decimates or asks for a finer profile, rather than stretching what it has.
  """
  @spec resolution(map()) :: float()
  def resolution(%{"points_per_second" => rate}), do: rate / 1

  def resolution(%{"points" => points, "duration_ms" => duration_ms}) when duration_ms > 0,
    do: points * 1000 / duration_ms

  @doc """
  Whether an artefact can be drawn at this many points per second without inventing
  anything.
  """
  @spec supports_zoom?(map(), number()) :: boolean()
  def supports_zoom?(descriptor, points_per_second),
    do: resolution(descriptor) >= points_per_second

  # Mono, because §20 asks for one channel: a stereo waveform drawn as one shape is
  # two shapes overlaid, and the registry says which this is.
  defp decode(location, target, sample_rate) do
    args =
      ~w(-loglevel error -nostdin -y -i) ++
        [Storage.path(location)] ++
        ["-ac", "1", "-ar", Integer.to_string(sample_rate), "-f", "s16le", target]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, "waveform_not_decoded", %{status: status, output: output}}
    end
  end

  defp sample_count(decoded) do
    case File.stat(decoded) do
      {:ok, %{size: size}} when size >= 2 -> {:ok, div(size, 2)}
      {:ok, %{size: size}} -> {:error, "waveform_has_no_samples", %{bytes: size}}
      {:error, reason} -> {:error, "waveform_unreadable", %{reason: inspect(reason)}}
    end
  end

  # Samples are divided into as many buckets as there are points, and each bucket
  # answers with its largest magnitude. The last bucket takes the remainder, so no
  # sample is dropped and no point is invented.
  defp bucket(decoded, samples, points) do
    per_point = max(div(samples, points), 1)

    decoded
    |> File.stream!([], @chunk_bytes)
    |> Stream.transform(<<>>, &split_samples/2)
    |> Stream.chunk_every(per_point)
    |> Stream.map(&to_byte(Enum.max(&1)))
    |> Enum.take(points)
  end

  defp split_samples(chunk, carry) do
    bytes = carry <> chunk
    whole = byte_size(bytes) - rem(byte_size(bytes), 2)
    <<samples::binary-size(whole), rest::binary>> = bytes

    {magnitudes(samples, []), rest}
  end

  defp magnitudes(<<sample::little-signed-16, rest::binary>>, acc),
    do: magnitudes(rest, [abs(sample) | acc])

  defp magnitudes(<<>>, acc), do: Enum.reverse(acc)

  # Eight bits unsigned, which is what the registry states. 32768 is one past the
  # largest magnitude a signed 16-bit sample reaches, so the division cannot answer
  # 256.
  defp to_byte(magnitude), do: div(magnitude * 256, 32_768)
end
