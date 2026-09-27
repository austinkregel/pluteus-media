defmodule Pluteus.Design.Colour do
  @moduledoc """
  The two instruments Annex A measures contrast with, and the conversions they
  need (A.2.1, A.2.4, A.2.5).

  A.2.5 pins both: the APCA algorithm at `0.0.98G-4g` as implemented in `apca-w3`
  0.1.9, and WCAG 2's relative-luminance formula as the conformance floor. Two
  instruments rather than one, because A.2.4 is explicit that "the WCAG 2 formula
  is known to overstate contrast between dark colours and this interface is
  dark-first", while §1.4.3 and §1.4.11 are what conformance is claimed against.

  **This is an implementation of a pinned algorithm, not a choice of algorithm.**
  It is calibrated against the two figures the annex publishes — step 11 at Lc 60.5
  and step 12 at Lc 95.5 against step 02 — which is what `colour_test.exs` asserts
  before anything else trusts it. A.2.4 records that the four floors "are the
  deployment's own, informed by APCA, and are not a conformance claim against it",
  because APCA's thresholds are not published in a versioned normative document.

  Colour is authored in OKLCH with an sRGB fallback, never computed by the build
  (A.2.1). These conversions exist to *check* the authored pairs agree and to
  derive the contexts the annex leaves to derivation, not to generate the values a
  person reads.
  """

  @typedoc "Red, green and blue, each 0 to 255."
  @type srgb :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}

  @doc """
  An OKLCH triple as sRGB, and whether it fell inside the gamut.

  Lightness is 0 to 1, chroma is absolute, hue is degrees. A colour outside sRGB
  is reported rather than silently clipped, because A.2.1 requires gamut mapping to
  reduce chroma at constant lightness and hue — which `fit_chroma/3` does — and a
  clipped channel changes hue as well as chroma.
  """
  @spec oklch(float(), float(), float()) :: {srgb(), :in_gamut | :out_of_gamut}
  def oklch(lightness, chroma, hue) do
    radians = hue * :math.pi() / 180
    a = chroma * :math.cos(radians)
    b = chroma * :math.sin(radians)

    long = cube(lightness + 0.3963377774 * a + 0.2158037573 * b)
    medium = cube(lightness - 0.1055613458 * a - 0.0638541728 * b)
    short = cube(lightness - 0.0894841775 * a - 1.2914855480 * b)

    linear = {
      4.0767416621 * long - 3.3077115913 * medium + 0.2309699292 * short,
      -1.2684380046 * long + 2.6097574011 * medium - 0.3413193965 * short,
      -0.0041960863 * long - 0.7034186147 * medium + 1.7076147010 * short
    }

    {encode(linear), gamut(linear)}
  end

  @doc """
  The largest chroma at this lightness and hue that stays inside sRGB, at most
  `chroma`.

  A.2.1: "Gamut mapping MUST reduce chroma at constant lightness and hue." Reducing
  lightness instead would break A.2.6's invariant, which is that one lightness
  across every hue holds measured contrast roughly constant.
  """
  @spec fit_chroma(float(), float(), float()) :: float()
  def fit_chroma(lightness, chroma, hue) do
    case oklch(lightness, chroma, hue) do
      {_srgb, :in_gamut} -> chroma
      {_srgb, :out_of_gamut} -> fit_chroma(lightness, chroma - 0.001, hue)
    end
  end

  @doc """
  WCAG 2's contrast ratio, the instrument conformance is claimed against
  ([WCAG22] §1.4.3, §1.4.11).
  """
  @spec contrast_ratio(srgb(), srgb()) :: float()
  def contrast_ratio(one, other) do
    {lighter, darker} = Enum.min_max([relative_luminance(one), relative_luminance(other)])
    (darker + 0.05) / (lighter + 0.05)
  end

  @doc """
  APCA lightness contrast, `Lc`, of text on a background.

  Signed in the algorithm and returned as a magnitude here, because A.2.4's floors
  are stated as magnitudes and polarity is carried by which argument is which.
  """
  @spec lc(srgb(), srgb()) :: float()
  def lc(text, background) do
    text_y = text |> apca_luminance() |> soft_clamp_black()
    background_y = background |> apca_luminance() |> soft_clamp_black()

    abs(sapc(text_y, background_y))
  end

  @doc """
  Euclidean distance in 8-bit sRGB, which A.2.6 states its hue separation in.
  """
  @spec distance(srgb(), srgb()) :: float()
  def distance({r1, g1, b1}, {r2, g2, b2}) do
    :math.sqrt(:math.pow(r1 - r2, 2) + :math.pow(g1 - g2, 2) + :math.pow(b1 - b2, 2))
  end

  @doc """
  `#rrggbb`, lower case, as the annex writes every fallback.
  """
  @spec to_hex(srgb()) :: String.t()
  def to_hex({r, g, b}) do
    "#" <> ([r, g, b] |> :erlang.list_to_binary() |> Base.encode16(case: :lower))
  end

  @doc """
  An `#rgb` or `#rrggbb` string as sRGB.
  """
  @spec from_hex(String.t()) :: srgb()
  def from_hex("#" <> digits) when byte_size(digits) == 6 do
    <<r, g, b>> = Base.decode16!(digits, case: :mixed)
    {r, g, b}
  end

  def from_hex("#" <> <<r, g, b>>), do: from_hex("#" <> <<r, r, g, g, b, b>>)

  defp cube(x), do: x * x * x

  defp gamut({r, g, b}) do
    if Enum.all?([r, g, b], &(&1 >= -0.0005 and &1 <= 1.0005)),
      do: :in_gamut,
      else: :out_of_gamut
  end

  defp encode({r, g, b}), do: {channel(r), channel(g), channel(b)}

  defp channel(linear) do
    linear |> max(0.0) |> min(1.0) |> transfer() |> Kernel.*(255) |> round()
  end

  defp transfer(u) when u <= 0.0031308, do: 12.92 * u
  defp transfer(u), do: 1.055 * :math.pow(u, 1 / 2.4) - 0.055

  # [WCAG22]'s own decoding, which is the sRGB piecewise transfer function and not
  # APCA's simple power curve. The two instruments do not share this step.
  defp relative_luminance({r, g, b}) do
    0.2126 * decode(r) + 0.7152 * decode(g) + 0.0722 * decode(b)
  end

  defp decode(value) do
    c = value / 255
    if c <= 0.04045, do: c / 12.92, else: :math.pow((c + 0.055) / 1.055, 2.4)
  end

  # APCA 0.98G-4g. The coefficients, exponents, scale and offsets are the pinned
  # algorithm's; none of them is a value this deployment chose.
  defp apca_luminance({r, g, b}) do
    0.2126729 * :math.pow(r / 255, 2.4) +
      0.7151522 * :math.pow(g / 255, 2.4) +
      0.0721750 * :math.pow(b / 255, 2.4)
  end

  defp soft_clamp_black(y) when y < 0.022, do: y + :math.pow(0.022 - y, 1.414)
  defp soft_clamp_black(y), do: y

  # Light text on a dark background, which is this interface's ordinary case.
  defp sapc(text_y, background_y) when background_y < text_y do
    contrast = (:math.pow(background_y, 0.65) - :math.pow(text_y, 0.62)) * 1.14

    if contrast > -0.1, do: 0.0, else: (contrast + 0.027) * 100
  end

  defp sapc(text_y, background_y) do
    contrast = (:math.pow(background_y, 0.56) - :math.pow(text_y, 0.57)) * 1.14

    if contrast < 0.1, do: 0.0, else: (contrast - 0.027) * 100
  end
end
