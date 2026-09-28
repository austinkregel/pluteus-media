defmodule PluteusWeb.IconTest do
  @moduledoc """
  Annex A.8's ladder, and the licence obligation A.8.1 states in full.

  A.8.1's reason for inline vectors is a silent failure: forced colours overrides
  `background-color`, so a masked element draws nothing for exactly the people most
  likely to be in that mode, and nothing anywhere reports it. So what is asserted here
  is the mechanism — `currentColor`, the right viewBox for the grid, and one drawing
  per band — rather than that the output looks right.
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Pluteus.Design.Icons
  alias PluteusWeb.Icon

  describe "A.8.1. Inline vectors taking their colour from the text colour" do
    test "a glyph is an svg and never a masked background" do
      html = render("hero-play-mini")

      assert html =~ "<svg"
      assert html =~ ~s(fill="currentColor")
      refute html =~ "background-color"
      refute html =~ "mask"
    end

    test "the 24 outline is stroked with currentColor at A.8.1's own width" do
      html = render("hero-play")

      assert html =~ ~s(fill="none")
      assert html =~ ~s(stroke="currentColor")
      assert html =~ ~s(stroke-width="1.5")
    end

    test "a glyph is hidden from assistive technology, so its label is its control's" do
      # An icon repeats what the control beside it says, and a screen reader announcing
      # both reads the same thing twice. Where the glyph is the whole of the control,
      # the control carries the label — which is why this is unconditional here.
      assert render("hero-x-mark-mini") =~ ~s(aria-hidden="true")
    end

    test "the licence and the permission notice travel with the copies" do
      # A.8.1: "The copyright notice and permission notice MUST travel with the
      # vendored copies and with any glyph derived from them", and that is the whole of
      # the obligation. The `sparse: "optimized"` checkout this replaced did not contain
      # the file, so the one thing the licence requires was the one thing missing.
      licence = File.read!(Path.join(Icons.root(), "LICENSE"))

      assert licence =~ "MIT License"
      assert licence =~ "Copyright (c) Tailwind Labs, Inc."
      assert licence =~ "The above copyright notice and this permission notice shall be included"
    end
  end

  describe "A.8.2. One variant per size band" do
    test "the drawing's own grid decides the rendered size" do
      assert render("hero-arrow-path-micro") =~ ~s(viewBox="0 0 16 16")
      assert render("hero-arrow-path-micro") =~ "size-4"

      assert render("hero-arrow-path-mini") =~ ~s(viewBox="0 0 20 20")
      assert render("hero-arrow-path-mini") =~ "size-5"

      assert render("hero-arrow-path") =~ ~s(viewBox="0 0 24 24")
      assert render("hero-arrow-path") =~ "size-6"
    end

    test "each grid is a separate drawing, not the same one three times" do
      # The claim A.8.1 rests the choice on, and the reason the band rule is worth
      # enforcing at all: if the three were one drawing scaled, there would be nothing
      # for a band to select and A.3.5's optical-size requirement would be unmet.
      drawings =
        ["hero-play-micro", "hero-play-mini", "hero-play"]
        |> Enum.map(&render/1)
        |> Enum.map(fn html -> html |> String.split(~s(d=")) |> Enum.at(1) end)

      assert Enum.uniq(drawings) == drawings
    end

    test "A.8.2's television figures come from the 24 outline, and only from it" do
      assert render("hero-play", 80) =~ "size-20"
      assert render("hero-play", 96) =~ "size-24"

      assert_raise ArgumentError, fn -> render("hero-play-mini", 96) end
      assert_raise ArgumentError, fn -> render("hero-play-micro", 80) end
    end

    test "every glyph is vendored at all three bands" do
      # A template placing a glyph in a band the set was not vendored at would raise,
      # which is loud but late. Vendoring all three means a band is always available,
      # and this is what says the task did that rather than that it happened to.
      for glyph <- Icons.inventory(), suffix <- Map.keys(Icons.bands()) do
        assert "hero-#{glyph}#{suffix}" in Icon.names()
      end
    end
  end

  describe "A.9.5. The vocabulary is enumerated, and a name outside it raises" do
    test "the names are exactly what is vendored, and every one has a drawing on disk" do
      expected =
        for glyph <- Icons.inventory(), suffix <- Map.keys(Icons.bands()) do
          "hero-#{glyph}#{suffix}"
        end

      assert Enum.sort(expected) == Icon.names()

      for {name, path, _grid} <- Icons.drawings() do
        assert File.exists?(path), "#{name} is in the vocabulary and #{path} is not on disk"
      end
    end

    test "a name the set does not carry raises rather than rendering nothing" do
      # The failure the Tailwind plugin had: a name it did not recognise produced no CSS
      # rule and the element rendered empty, with no error anywhere. A name is now a key
      # into what was vendored, so the same mistake is a raise at the call site.
      assert_raise KeyError, fn -> render("hero-plaay-mini") end
      assert_raise KeyError, fn -> render("hero-play-solid") end
    end

    test "every glyph the interface names is one the set carries" do
      # Read from the source that names it, so a glyph added to a template without being
      # vendored fails here rather than at the moment somebody opens that page.
      named =
        Path.join(File.cwd!(), "lib/pluteus_web/**/*.{ex,heex}")
        |> Path.wildcard()
        |> Enum.flat_map(fn file ->
          Regex.scan(~r/"(hero-[a-z0-9-]+)"/, File.read!(file), capture: :all_but_first)
        end)
        |> List.flatten()
        |> Enum.uniq()

      assert named != [], "no glyph was found in the source, so this asserts nothing"

      for name <- named do
        assert name in Icon.names(), "#{name} is named in a template and is not vendored"
      end
    end
  end

  defp render(name, size \\ nil) do
    %{name: name, size: size, class: nil, __changed__: nil}
    |> Icon.icon()
    |> rendered_to_string()
  end
end
