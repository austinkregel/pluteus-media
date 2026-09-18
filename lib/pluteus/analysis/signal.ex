defmodule Pluteus.Analysis.Signal do
  @moduledoc """
  Signal measurements computed on the BEAM from decoded samples: level,
  loudness per ITU-R BS.1770, and features of the short-time spectrum.

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

  @doc """
  RMS and peak level in dBFS.
  """
  @spec level([float()]) :: map()
  def level([]), do: %{}

  def level(samples) do
    mean_square = Enum.reduce(samples, 0.0, &(&1 * &1 + &2)) / length(samples)
    peak = samples |> Enum.map(&abs/1) |> Enum.max()

    %{}
    |> put_db("rms_dbfs", :math.sqrt(mean_square))
    |> put_db("peak_dbfs", peak)
  end

  defp put_db(measurements, _name, amplitude) when amplitude <= 0.0, do: measurements

  defp put_db(measurements, name, amplitude),
    do: Map.put(measurements, name, 20 * :math.log10(amplitude))

  # BS.1770-4's K-weighting at 48 kHz: a high-shelf pre-filter and a high-pass.
  @shelf {[1.53512485958697, -2.69169618940638, 1.19839281085285],
          [1.0, -1.69065929318241, 0.73248077421585]}
  @high_pass {[1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621]}

  @doc """
  Integrated loudness in LUFS of mono samples at 48 kHz: K-weighted, in 400 ms
  blocks overlapping by 75%, gated absolutely at -70 LUFS and then relatively
  at 10 LU below the absolutely gated mean.
  """
  @spec loudness([float()]) :: map()
  def loudness(samples_48k) do
    weighted = samples_48k |> biquad(@shelf) |> biquad(@high_pass) |> List.to_tuple()
    block = 19_200
    step = 4_800

    blocks =
      if tuple_size(weighted) < block,
        do: [],
        else:
          for(
            start <- 0..(tuple_size(weighted) - block)//step,
            do: mean_square(weighted, start, block)
          )

    absolute = Enum.filter(blocks, &(block_loudness(&1) > -70.0))

    case absolute do
      [] ->
        %{}

      _ ->
        relative_gate = block_loudness(Enum.sum(absolute) / length(absolute)) - 10.0

        case Enum.filter(absolute, &(block_loudness(&1) > relative_gate)) do
          [] -> %{}
          gated -> %{"loudness_lufs" => block_loudness(Enum.sum(gated) / length(gated))}
        end
    end
  end

  defp block_loudness(mean_square) when mean_square <= 0.0, do: -1.0e9
  defp block_loudness(mean_square), do: -0.691 + 10 * :math.log10(mean_square)

  defp mean_square(samples, start, count) do
    Enum.reduce(start..(start + count - 1), 0.0, fn i, acc ->
      x = elem(samples, i)
      acc + x * x
    end) / count
  end

  defp biquad(samples, {[b0, b1, b2], [_a0, a1, a2]}) do
    {output, _state} =
      Enum.map_reduce(samples, {0.0, 0.0, 0.0, 0.0}, fn x, {x1, x2, y1, y2} ->
        y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        {y, {x, x1, y, y1}}
      end)

    output
  end

  @doc """
  Means over short-time frames of: spectral centroid, 85% rolloff and flux;
  log energy in #{@mel_bands} mel bands; the first #{@mfcc_coefficients} MFCCs;
  and chroma, the spectrum's energy in each of the twelve pitch classes.
  """
  @spec spectral([float()], pos_integer()) :: map()
  def spectral(samples, sample_rate) do
    spectra = samples |> frames() |> Enum.map(&power_spectrum/1)
    bin_hz = sample_rate / @window
    filters = mel_filters(sample_rate)

    per_frame =
      Enum.map(spectra, fn power ->
        log_mel = Enum.map(filters, &:math.log(dot(&1, power) + 1.0e-10))

        %{
          centroid: centroid(power, bin_hz),
          rolloff: rolloff(power, bin_hz),
          log_mel: log_mel,
          mfcc: dct(log_mel),
          chroma: chroma(power, bin_hz)
        }
      end)

    flux =
      spectra
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> :math.sqrt(Enum.sum(Enum.zip_with(a, b, &((&2 - &1) ** 2)))) end)

    %{
      "spectral_centroid_hz" => mean(Enum.map(per_frame, & &1.centroid)),
      "spectral_rolloff_hz" => mean(Enum.map(per_frame, & &1.rolloff))
    }
    |> Map.merge(if flux == [], do: %{}, else: %{"spectral_flux" => mean(flux)})
    |> Map.merge(named("mel_", Enum.map(per_frame, & &1.log_mel)))
    |> Map.merge(named("mfcc_", Enum.map(per_frame, & &1.mfcc)))
    |> Map.merge(
      per_frame
      |> Enum.map(& &1.chroma)
      |> columns_mean()
      |> Enum.zip(@pitch_classes)
      |> Map.new(fn {value, pitch} -> {"chroma_" <> pitch, value} end)
    )
  end

  defp named(prefix, rows) do
    rows
    |> columns_mean()
    |> Enum.with_index(1)
    |> Map.new(fn {value, index} -> {prefix <> String.pad_leading("#{index}", 2, "0"), value} end)
  end

  defp columns_mean(rows), do: rows |> Enum.zip_with(& &1) |> Enum.map(&mean/1)

  defp mean(values), do: Enum.sum(values) / length(values)

  defp frames(samples) do
    padded =
      if length(samples) < @window,
        do: samples ++ List.duplicate(0.0, @window - length(samples)),
        else: samples

    hann =
      for n <- 0..(@window - 1), do: 0.5 - 0.5 * :math.cos(2 * :math.pi() * n / (@window - 1))

    padded
    |> Enum.chunk_every(@window, @hop, :discard)
    |> Enum.map(&Enum.zip_with(&1, hann, fn x, w -> x * w end))
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
    n = length(xs)
    {evens, odds} = xs |> Enum.with_index() |> Enum.split_with(fn {_x, i} -> rem(i, 2) == 0 end)
    even = evens |> Enum.map(&elem(&1, 0)) |> fft()
    odd = odds |> Enum.map(&elem(&1, 0)) |> fft()

    twiddled =
      odd
      |> Enum.with_index()
      |> Enum.map(fn {{re, im}, k} ->
        angle = -2 * :math.pi() * k / n
        {c, s} = {:math.cos(angle), :math.sin(angle)}
        {re * c - im * s, re * s + im * c}
      end)

    Enum.zip_with(even, twiddled, fn {er, ei}, {tr, ti} -> {er + tr, ei + ti} end) ++
      Enum.zip_with(even, twiddled, fn {er, ei}, {tr, ti} -> {er - tr, ei - ti} end)
  end

  defp centroid(power, bin_hz) do
    total = Enum.sum(power)

    if total == 0.0,
      do: 0.0,
      else:
        power
        |> Enum.with_index()
        |> Enum.reduce(0.0, fn {p, k}, acc -> acc + p * k * bin_hz end)
        |> Kernel./(total)
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
    top = mel(sample_rate / 2)
    edges = for i <- 0..(@mel_bands + 1), do: hz(top * i / (@mel_bands + 1))
    bins = for k <- 0..div(@window, 2), do: k * sample_rate / @window

    edges
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.map(fn [low, centre, high] -> Enum.map(bins, &triangle(&1, low, centre, high)) end)
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
