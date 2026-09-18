defmodule Pluteus.Analysis.Native do
  @moduledoc """
  The analysing tool that runs in the deployment, on the BEAM (spec-04 §8.2).

  ffmpeg decodes the requested stream and extent to mono PCM and streams it
  through a port; everything measured from the samples is computed here as
  they arrive: level, BS.1770 loudness, and the short-time spectrum's centroid,
  rolloff, flux, mel bands, MFCCs and chroma. Memory stays bounded however long
  the recording is.

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
    spectral_start = {Signal.new_level(), Signal.new_spectral(@spectral_rate)}

    with {:ok, {level, spectral}} <-
           fold_decoded(request, @spectral_rate, spectral_start, fn samples, {level, spectral} ->
             {Signal.feed_level(level, samples), Signal.feed_spectral(spectral, samples)}
           end),
         {:ok, loudness} <-
           fold_decoded(
             request,
             @loudness_rate,
             Signal.new_loudness(),
             &Signal.feed_loudness(&2, &1)
           ) do
      measurements =
        level
        |> Signal.finish_level()
        |> Map.merge(Signal.finish_loudness(loudness))
        |> Map.merge(Signal.finish_spectral(spectral))

      {:ok, %{"schema_version" => @schema_version, "measurements" => measurements}}
    end
  end

  # Runs ffmpeg with its output on a port and folds each chunk of samples into
  # the accumulator as it arrives. A float split across two chunks is carried
  # into the next.
  defp fold_decoded(request, rate, acc, fun) do
    args =
      ["-loglevel", "error", "-nostdin"] ++
        extent(request) ++
        ["-i", request.path, "-map", stream(request)] ++
        ["-ac", "1", "-ar", "#{rate}", "-f", "f32le", "-"]

    port =
      Port.open({:spawn_executable, System.find_executable("ffmpeg")}, [
        :binary,
        :exit_status,
        args: args
      ])

    receive_samples(port, acc, fun, <<>>, 0)
  end

  defp receive_samples(port, acc, fun, carry, decoded) do
    receive do
      {^port, {:data, chunk}} ->
        {samples, rest} = samples(carry, chunk)
        receive_samples(port, fun.(samples, acc), fun, rest, decoded + length(samples))

      {^port, {:exit_status, 0}} when decoded > 0 ->
        {:ok, acc}

      {^port, {:exit_status, 0}} ->
        {:error, :permanent, :no_samples_decoded}

      {^port, {:exit_status, status}} ->
        {:error, :permanent, {:ffmpeg, status}}
    end
  end

  @doc """
  The whole 32-bit little-endian floats in what was carried over and a new
  chunk, and the bytes of a float the chunk ended partway through.
  """
  @spec samples(binary(), binary()) :: {[float()], binary()}
  def samples(carry, chunk) do
    bytes = carry <> chunk
    whole = byte_size(bytes) - rem(byte_size(bytes), 4)
    <<complete::binary-size(whole), rest::binary>> = bytes
    {for(<<x::float-32-little <- complete>>, do: x), rest}
  end

  defp stream(%{stream_index: nil}), do: "0:a:0"
  defp stream(%{stream_index: index}), do: "0:#{index}"

  defp extent(%{start_ms: nil}), do: []

  defp extent(%{start_ms: start, end_ms: finish}),
    do: ["-ss", seconds(start), "-to", seconds(finish)]

  defp seconds(ms), do: :erlang.float_to_binary(ms / 1000, decimals: 3)
end
