defmodule Pluteus.Analysis.Native do
  @moduledoc """
  The analysing tool that runs in the deployment, on the BEAM (spec-04 §8.2).

  ffmpeg decodes the requested stream and extent to mono PCM; everything
  measured from the samples is computed here: level, BS.1770 loudness, and the
  short-time spectrum's centroid, rolloff, flux, mel bands, MFCCs and chroma.

  The version names the algorithm. Changing what is computed, or how, changes
  it, which makes everything measured at the earlier version due again.
  """

  @behaviour Pluteus.Analysis.Tool

  alias Pluteus.Analysis.Signal

  @name "pluteus-native"
  @version "1"
  @schema_version 1
  @spectral_rate 22_050
  @loudness_rate 48_000

  @impl true
  def describe, do: {:ok, %{name: @name, version: @version, schema_version: @schema_version}}

  @impl true
  def analyse(request) do
    with {:ok, spectral} <- decode(request, @spectral_rate),
         {:ok, loudness} <- decode(request, @loudness_rate) do
      measurements =
        spectral
        |> Signal.level()
        |> Map.merge(Signal.loudness(loudness))
        |> Map.merge(Signal.spectral(spectral, @spectral_rate))

      {:ok, %{"schema_version" => @schema_version, "measurements" => measurements}}
    end
  end

  defp decode(request, rate) do
    args =
      ["-loglevel", "error", "-nostdin"] ++
        extent(request) ++
        [
          "-i",
          request.path,
          "-map",
          stream(request),
          "-ac",
          "1",
          "-ar",
          "#{rate}",
          "-f",
          "f32le",
          "-"
        ]

    case System.cmd("ffmpeg", args, stderr_to_stdout: false) do
      {pcm, 0} when byte_size(pcm) > 0 -> {:ok, for(<<x::float-32-little <- pcm>>, do: x)}
      {_pcm, 0} -> {:error, :permanent, :no_samples_decoded}
      {_output, status} -> {:error, :permanent, {:ffmpeg, status}}
    end
  end

  defp stream(%{stream_index: nil}), do: "0:a:0"
  defp stream(%{stream_index: index}), do: "0:#{index}"

  defp extent(%{start_ms: nil}), do: []

  defp extent(%{start_ms: start, end_ms: finish}),
    do: ["-ss", seconds(start), "-to", seconds(finish)]

  defp seconds(ms), do: :erlang.float_to_binary(ms / 1000, decimals: 3)
end
