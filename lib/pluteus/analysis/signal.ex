defmodule Pluteus.Analysis.Signal do
  @moduledoc """
  Signal measurements computed on the BEAM from decoded samples: level,
  loudness per ITU-R BS.1770, and features of the short-time spectrum.

  Each family of measurements is an accumulator: started with `new_*`, fed
  samples in chunks as they are decoded, and finished into measurements. A
  recording of any length is measured in bounded memory, since no family holds
  more than a window of samples, and loudness holds one mean square per 100 ms.

  Samples are mono floats in [-1, 1]. A measurement that is undefined for the
  samples given — the level of silence, the loudness of a signal entirely below
  the absolute gate — is absent from the result rather than given a stand-in
  value.
  """

  @window 2048
  @hop 1024
  @mel_bands 40
  @mfcc_coefficients 13
  @pitch_classes ~w(c c_sharp d d_sharp e f f_sharp g g_sharp a a_sharp b)

  # --- Level -------------------------------------------------------------------

  @spec new_level() :: map()
  def new_level, do: %{sum_squares: 0.0, count: 0, peak: 0.0}

  @spec feed_level(map(), [float()]) :: map()
  def feed_level(level, samples) do
    Enum.reduce(samples, level, fn x, %{sum_squares: s, count: n, peak: p} ->
      %{sum_squares: s + x * x, count: n + 1, peak: max(p, abs(x))}
    end)
  end

  @doc """
  RMS and peak level in dBFS.
  """
  @spec finish_level(map()) :: map()
  def finish_level(%{count: 0}), do: %{}

  def finish_level(%{sum_squares: s, count: n, peak: peak}) do
    %{}
    |> put_db("rms_dbfs", :math.sqrt(s / n))
    |> put_db("peak_dbfs", peak)
  end

  @spec level([float()]) :: map()
  def level(samples), do: new_level() |> feed_level(samples) |> finish_level()

  defp put_db(measurements, _name, amplitude) when amplitude <= 0.0, do: measurements

  defp put_db(measurements, name, amplitude),
    do: Map.put(measurements, name, 20 * :math.log10(amplitude))

  # --- Loudness ------------------------------------------------------------------

  # BS.1770-4's K-weighting at 48 kHz: a high-shelf pre-filter and a high-pass.
  @shelf {[1.53512485958697, -2.69169618940638, 1.19839281085285],
          [1.0, -1.69065929318241, 0.73248077421585]}
  @high_pass {[1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621]}

  # 100 ms at 48 kHz. A gating block is four of them, 400 ms, and consecutive
  # blocks start one sub-block apart, which is BS.1770's 75% overlap.
  @sub_block 4_800

  @spec new_loudness() :: map()
  def new_loudness do
    %{
      shelf: {0.0, 0.0, 0.0, 0.0},
      high_pass: {0.0, 0.0, 0.0, 0.0},
      sum: 0.0,
      count: 0,
      sub_blocks: []
    }
  end

  @doc """
  Feeds mono samples at 48 kHz.
  """
  @spec feed_loudness(map(), [float()]) :: map()
  def feed_loudness(loudness, samples) do
    Enum.reduce(samples, loudness, fn x, acc ->
      {y1, shelf} = biquad_step(x, acc.shelf, @shelf)
      {y, high_pass} = biquad_step(y1, acc.high_pass, @high_pass)

      close_sub_block(%{
        acc
        | shelf: shelf,
          high_pass: high_pass,
          sum: acc.sum + y * y,
          count: acc.count + 1
      })
    end)
  end

  defp close_sub_block(%{count: @sub_block} = acc),
    do: %{acc | sum: 0.0, count: 0, sub_blocks: [acc.sum / @sub_block | acc.sub_blocks]}

  defp close_sub_block(acc), do: acc

  @doc """
  Integrated loudness in LUFS: K-weighted, in 400 ms blocks overlapping by 75%,
  gated absolutely at -70 LUFS and then relatively at 10 LU below the
  absolutely gated mean.
  """
  @spec finish_loudness(map()) :: map()
  def finish_loudness(%{sub_blocks: sub_blocks}) do
    blocks =
      sub_blocks
      |> Enum.reverse()
      |> Enum.chunk_every(4, 1, :discard)
      |> Enum.map(&(Enum.sum(&1) / 4))

    with [_ | _] = absolute <- Enum.filter(blocks, &(block_loudness(&1) > -70.0)),
         gate = block_loudness(mean(absolute)) - 10.0,
         [_ | _] = gated <- Enum.filter(absolute, &(block_loudness(&1) > gate)) do
      %{"loudness_lufs" => block_loudness(mean(gated))}
    else
      [] -> %{}
    end
  end

  @spec loudness([float()]) :: map()
  def loudness(samples_48k),
    do: new_loudness() |> feed_loudness(samples_48k) |> finish_loudness()

  defp block_loudness(mean_square) when mean_square <= 0.0, do: -1.0e9
  defp block_loudness(mean_square), do: -0.691 + 10 * :math.log10(mean_square)

  defp biquad_step(x, {x1, x2, y1, y2}, {[b0, b1, b2], [_a0, a1, a2]}) do
    y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
    {y, {x, x1, y, y1}}
  end

  # --- Spectrum ------------------------------------------------------------------

  @spec new_spectral(pos_integer()) :: map()
  def new_spectral(sample_rate) do
    %{
      bin_hz: sample_rate / @window,
      filters: mel_filters(sample_rate),
      pending: [],
      pending_count: 0,
      frames: 0,
      previous: nil,
      centroid: 0.0,
      rolloff: 0.0,
      flux: 0.0,
      flux_frames: 0,
      mel: List.duplicate(0.0, @mel_bands),
      mfcc: List.duplicate(0.0, @mfcc_coefficients),
      chroma: List.duplicate(0.0, 12)
    }
  end

  @doc """
  Feeds mono samples at the rate the accumulator was started with. Every full
  window is measured as it becomes available; what remains waits for the next
  chunk.
  """
  @spec feed_spectral(map(), [float()]) :: map()
  def feed_spectral(spectral, samples) do
    drain(%{
      spectral
      | pending: spectral.pending ++ samples,
        pending_count: spectral.pending_count + length(samples)
    })
  end

  defp drain(%{pending_count: count} = spectral) when count < @window, do: spectral

  defp drain(spectral) do
    {frame, _rest} = Enum.split(spectral.pending, @window)

    spectral
    |> measure_frame(frame)
    |> Map.merge(%{
      pending: Enum.drop(spectral.pending, @hop),
      pending_count: spectral.pending_count - @hop
    })
    |> drain()
  end

  defp measure_frame(spectral, frame) do
    power = frame |> Enum.zip_with(hann(), &*/2) |> power_spectrum()
    log_mel = Enum.map(spectral.filters, &:math.log(dot(&1, power) + 1.0e-10))

    spectral
    |> Map.merge(flux(spectral, power))
    |> Map.merge(%{
      frames: spectral.frames + 1,
      previous: power,
      centroid: spectral.centroid + centroid(power, spectral.bin_hz),
      rolloff: spectral.rolloff + rolloff(power, spectral.bin_hz),
      mel: add(spectral.mel, log_mel),
      mfcc: add(spectral.mfcc, dct(log_mel)),
      chroma: add(spectral.chroma, chroma(power, spectral.bin_hz))
    })
  end

  defp flux(%{previous: nil}, _power), do: %{}

  defp flux(spectral, power) do
    change = :math.sqrt(Enum.sum(Enum.zip_with(spectral.previous, power, &((&2 - &1) ** 2))))
    %{flux: spectral.flux + change, flux_frames: spectral.flux_frames + 1}
  end

  @doc """
  Means over short-time frames of: spectral centroid, 85% rolloff and flux;
  log energy in #{@mel_bands} mel bands; the first #{@mfcc_coefficients} MFCCs;
  and chroma, the spectrum's energy in each of the twelve pitch classes. Input
  shorter than one window is measured as one zero-padded window.
  """
  @spec finish_spectral(map()) :: map()
  def finish_spectral(%{frames: 0, pending_count: 0}), do: %{}

  def finish_spectral(%{frames: 0} = spectral) do
    padding = List.duplicate(0.0, @window - spectral.pending_count)
    finish_spectral(measure_frame(spectral, spectral.pending ++ padding))
  end

  def finish_spectral(spectral) do
    n = spectral.frames

    %{
      "spectral_centroid_hz" => spectral.centroid / n,
      "spectral_rolloff_hz" => spectral.rolloff / n
    }
    |> Map.merge(flux_mean(spectral))
    |> Map.merge(numbered("mel_", spectral.mel, n))
    |> Map.merge(numbered("mfcc_", spectral.mfcc, n))
    |> Map.merge(
      spectral.chroma
      |> Enum.zip(@pitch_classes)
      |> Map.new(fn {sum, pitch} -> {"chroma_" <> pitch, sum / n} end)
    )
  end

  defp flux_mean(%{flux_frames: 0}), do: %{}
  defp flux_mean(spectral), do: %{"spectral_flux" => spectral.flux / spectral.flux_frames}

  @spec spectral([float()], pos_integer()) :: map()
  def spectral(samples, sample_rate),
    do: sample_rate |> new_spectral() |> feed_spectral(samples) |> finish_spectral()

  defp numbered(prefix, sums, n) do
    sums
    |> Enum.with_index(1)
    |> Map.new(fn {sum, index} -> {prefix <> String.pad_leading("#{index}", 2, "0"), sum / n} end)
  end

  defp add(sums, values), do: Enum.zip_with(sums, values, &+/2)

  defp mean(values), do: Enum.sum(values) / length(values)

  defp hann do
    cached({:hann, @window}, fn ->
      for n <- 0..(@window - 1), do: 0.5 - 0.5 * :math.cos(2 * :math.pi() * n / (@window - 1))
    end)
  end

  defp power_spectrum(frame) do
    frame
    |> Enum.map(&{&1, 0.0})
    |> fft()
    |> Enum.take(div(@window, 2) + 1)
    |> Enum.map(fn {re, im} -> re * re + im * im end)
  end

  @doc """
  The discrete Fourier transform of a list of complex numbers, as `{re, im}`,
  whose length is a power of two.
  """
  @spec fft([{float(), float()}]) :: [{float(), float()}]
  def fft([x]), do: [x]

  def fft(xs) do
    {evens, odds} = split(xs, [], [])
    combine(fft(evens), fft(odds), twiddles(length(xs)), [], [])
  end

  defp split([a, b | rest], evens, odds), do: split(rest, [a | evens], [b | odds])
  defp split([], evens, odds), do: {Enum.reverse(evens), Enum.reverse(odds)}

  defp combine([{er, ei} | evens], [{odd_re, odd_im} | odds], [{c, s} | twiddles], top, bottom) do
    tr = odd_re * c - odd_im * s
    ti = odd_re * s + odd_im * c
    combine(evens, odds, twiddles, [{er + tr, ei + ti} | top], [{er - tr, ei - ti} | bottom])
  end

  defp combine([], [], [], top, bottom), do: Enum.reverse(top) ++ Enum.reverse(bottom)

  defp twiddles(n) do
    cached({:twiddles, n}, fn ->
      for k <- 0..(div(n, 2) - 1) do
        angle = -2 * :math.pi() * k / n
        {:math.cos(angle), :math.sin(angle)}
      end
    end)
  end

  defp cached(key, compute) do
    case :persistent_term.get({__MODULE__, key}, nil) do
      nil ->
        value = compute.()
        :persistent_term.put({__MODULE__, key}, value)
        value

      value ->
        value
    end
  end

  defp centroid(power, bin_hz) do
    total = Enum.sum(power)

    if total == 0.0 do
      0.0
    else
      power
      |> Enum.with_index()
      |> Enum.reduce(0.0, fn {p, k}, acc -> acc + p * k * bin_hz end)
      |> Kernel./(total)
    end
  end

  defp rolloff(power, bin_hz) do
    threshold = 0.85 * Enum.sum(power)

    power
    |> Enum.scan(&+/2)
    |> Enum.find_index(&(&1 >= threshold))
    |> Kernel.||(0)
    |> Kernel.*(bin_hz)
  end

  defp dot(weights, power), do: Enum.sum(Enum.zip_with(weights, power, &*/2))

  defp mel(hz), do: 2595 * :math.log10(1 + hz / 700)
  defp hz(mel), do: 700 * (10 ** (mel / 2595) - 1)

  defp mel_filters(sample_rate) do
    cached({:mel_filters, sample_rate}, fn ->
      top = mel(sample_rate / 2)
      edges = for i <- 0..(@mel_bands + 1), do: hz(top * i / (@mel_bands + 1))
      bins = for k <- 0..div(@window, 2), do: k * sample_rate / @window

      edges
      |> Enum.chunk_every(3, 1, :discard)
      |> Enum.map(fn [low, centre, high] -> Enum.map(bins, &triangle(&1, low, centre, high)) end)
    end)
  end

  defp triangle(f, low, centre, _high) when f > low and f <= centre,
    do: (f - low) / (centre - low)

  defp triangle(f, _low, centre, high) when f > centre and f < high,
    do: (high - f) / (high - centre)

  defp triangle(_f, _low, _centre, _high), do: 0.0

  # DCT-II, orthonormal, of the log mel energies.
  defp dct(values) do
    n = length(values)

    for k <- 0..(@mfcc_coefficients - 1) do
      scale = if k == 0, do: :math.sqrt(1 / n), else: :math.sqrt(2 / n)

      values
      |> Enum.with_index()
      |> Enum.reduce(0.0, fn {v, i}, acc ->
        acc + v * :math.cos(:math.pi() * k * (2 * i + 1) / (2 * n))
      end)
      |> Kernel.*(scale)
    end
  end

  # Each bin's power goes to the pitch class of its centre frequency, over the
  # range of a piano. A frame's chroma is scaled so its strongest class is 1.
  defp chroma(power, bin_hz) do
    classes =
      power
      |> Enum.with_index()
      |> Enum.reduce(List.duplicate(0.0, 12), fn {p, k}, acc ->
        f = k * bin_hz

        if f >= 27.5 and f <= 4186.0 do
          pitch = rem(round(12 * :math.log2(f / 440.0)) + 9 + 1200, 12)
          List.update_at(acc, pitch, &(&1 + p))
        else
          acc
        end
      end)

    case Enum.max(classes) do
      max when max > 0.0 -> Enum.map(classes, &(&1 / max))
      _silent -> classes
    end
  end
end
