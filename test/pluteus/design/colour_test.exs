defmodule Pluteus.Design.ColourTest do
  @moduledoc """
  Calibration of the two instruments Annex A.2.5 pins, before anything else trusts
  them.

  A.2.5 pins APCA at `0.0.98G-4g` as implemented in `apca-w3` 0.1.9, and A.2.4's
  four floors are measured with it. An implementation that disagreed with the pinned
  one would move every floor silently, so it is calibrated here against the figures
  the annex publishes rather than assumed correct.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Design.Colour

  @step_02 "#18191c"
  @step_11 "#b0b4bd"
  @step_12 "#eceef2"

  describe "A.2.5. The instruments agree with the figures the annex publishes" do
    test "every OKLCH triple in the ramp round-trips to its stated hex" do
      # A.2.1 authors colour in OKLCH with an sRGB fallback and forbids the build
      # computing either. That only holds if the two agree, so this is the check
      # that the authored pairs are the same colour twice and not two colours.
      ramp = [
        {0.178, 0.004, 264, "#101113"},
        {0.213, 0.006, 264, "#18191c"},
        {0.252, 0.008, 264, "#202226"},
        {0.279, 0.009, 264, "#26292d"},
        {0.305, 0.010, 264, "#2c2f34"},
        {0.345, 0.011, 264, "#36393f"},
        {0.400, 0.012, 264, "#44484e"},
        {0.487, 0.013, 264, "#5c6067"},
        {0.545, 0.014, 264, "#6c7079"},
        {0.600, 0.014, 264, "#7c8089"},
        {0.770, 0.013, 264, "#b0b4bd"},
        {0.949, 0.006, 264, "#eceef2"}
      ]

      for {lightness, chroma, hue, hex} <- ramp do
        assert {srgb, :in_gamut} = Colour.oklch(lightness, chroma, hue)
        assert Colour.to_hex(srgb) == hex, "oklch(#{lightness} #{chroma} #{hue})"
      end
    end

    test "every class colour round-trips, and the focus ring with them" do
      classes = [
        {0.72, 0.146, 275, "#8b9bff"},
        {0.72, 0.150, 75, "#da950b"},
        {0.72, 0.170, 138, "#6abd4b"},
        {0.72, 0.126, 185, "#08beaf"},
        {0.72, 0.160, 12, "#f7758a"}
      ]

      for {lightness, chroma, hue, hex} <- classes do
        assert {srgb, :in_gamut} = Colour.oklch(lightness, chroma, hue)
        assert Colour.to_hex(srgb) == hex
      end

      assert {ring, :in_gamut} = Colour.oklch(0.62, 0.012, 264)
      assert Colour.to_hex(ring) == "#82868e"
    end

    test "WCAG 2 reproduces A.2.2's two stated ratios" do
      ground = Colour.from_hex(@step_02)

      assert_in_delta Colour.contrast_ratio(Colour.from_hex(@step_11), ground), 8.46, 0.01
      assert_in_delta Colour.contrast_ratio(Colour.from_hex(@step_12), ground), 15.13, 0.01
    end

    test "APCA reproduces A.2.2's stated Lc for step 11" do
      # The annex states Lc 60.5, which is what this must agree with for A.2.4's
      # floors to mean what they say.
      assert_in_delta Colour.lc(Colour.from_hex(@step_11), Colour.from_hex(@step_02)), 60.5, 0.05
    end

    test "APCA gives step 12 Lc 95.4, where the annex says 95.5" do
      # A discrepancy of 0.1, recorded rather than rounded away. Both figures are far
      # above A.2.4's Lc 75 body-text floor, so nothing rests on it; but A.2.5 pins
      # the instrument, so the prose should be re-read off the pinned package rather
      # than this assertion bent to match the prose.
      measured = Colour.lc(Colour.from_hex(@step_12), Colour.from_hex(@step_02))

      assert_in_delta measured, 95.4, 0.05
      refute_in_delta measured, 95.5, 0.04
    end

    test "A.6's border and surface ratios come out as the annex measured them" do
      steps = ~w(#101113 #18191c #202226 #26292d #2c2f34) |> Enum.map(&Colour.from_hex/1)

      # Step 03 on step 02: the 1.10:1 that is why a tonal step cannot carry a
      # boundary, and therefore why A.6 requires a border on a significant edge.
      assert_in_delta Colour.contrast_ratio(
                        Colour.from_hex("#202226"),
                        Colour.from_hex(@step_02)
                      ),
                      1.10,
                      0.01

      # The focus ring's primitive, which `sys.color.border.strong` also resolves to,
      # clears 3:1 against every one of the five elevation surfaces.
      ring = Colour.from_hex("#82868e")
      measured = Enum.map(steps, &Colour.contrast_ratio(ring, &1))

      assert [first | _rest] = measured
      assert_in_delta first, 5.17, 0.01
      assert_in_delta List.last(measured), 3.68, 0.01
      assert Enum.all?(measured, &(&1 >= 3.0))
    end

    test "gamut mapping reduces chroma and leaves lightness and hue alone" do
      # A.2.1's rule. At lightness 0.80 the class hues need it; the check is that
      # what comes back is in gamut and that nothing raised the chroma to get there.
      for {chroma, hue} <- [{0.146, 275}, {0.150, 75}, {0.170, 138}, {0.126, 185}, {0.160, 12}] do
        fitted = Colour.fit_chroma(0.80, chroma, hue)

        assert fitted <= chroma
        assert {_srgb, :in_gamut} = Colour.oklch(0.80, fitted, hue)
      end
    end

    test "hex parsing round-trips both lengths" do
      assert Colour.from_hex("#8b9bff") == {139, 155, 255}
      assert Colour.from_hex("#abc") == Colour.from_hex("#aabbcc")
      assert Colour.to_hex({139, 155, 255}) == "#8b9bff"
    end
  end
end
