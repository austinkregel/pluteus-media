defmodule PluteusWeb.CoreComponentsTest do
  @moduledoc """
  Annex A.8.2's size bands and A.9.5's loud variants.

  Both name a failure that produces no error. A glyph scaled outside its band renders
  — it is simply the wrong drawing, and at 16 px an outline's counters have closed so
  it reads as a grey lozenge. A class name assembled at run time produces no CSS rule
  at all, so the element is an empty span rather than a wrong one, which is the harder
  of the two to notice.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias PluteusWeb.CoreComponents

  describe "A.8.2. One variant per size band" do
    test "the drawing's own grid decides the rendered size" do
      # The suffix and the dimension cannot disagree because there is no second thing
      # to pass. 16 and 20 are separate artwork rather than the 24 scaled down, which
      # is what earns the set its place under A.3.5's optical-size requirement.
      assert icon(%{name: "hero-arrow-path-micro"}) =~ "size-4"
      assert icon(%{name: "hero-arrow-path-mini"}) =~ "size-5"
      assert icon(%{name: "hero-arrow-path"}) =~ "size-6"
    end

    test "A.8.2's television figures come from the 24 outline, and only from it" do
      # 80 px minimum and 96 preferred. A small grid asked for at that size raises,
      # because scaling a 16 px drawing to 96 is the one thing A.8.2 forbids outright.
      assert icon(%{name: "hero-play", size: 80}) =~ "size-20"
      assert icon(%{name: "hero-play", size: 96}) =~ "size-24"

      assert_raise ArgumentError, fn -> icon(%{name: "hero-play-mini", size: 96}) end
      assert_raise ArgumentError, fn -> icon(%{name: "hero-play-micro", size: 80}) end
    end

    test "the name reaches the markup whole, so the CSS build can see it" do
      # A.9.5's real requirement. Were the component to assemble `hero-` and a suffix
      # the class would still appear here and still generate no rule, so this asserts
      # the name arrives as one literal string rather than that the output looks right.
      assert icon(%{name: "hero-x-mark-mini"}) =~ ~s(class="hero-x-mark-mini size-5")
    end

    test "every glyph the interface names exists in the set at the grid it asks for" do
      # The failure this catches is silent twice over: a misspelt glyph, or one the 16
      # grid does not carry — the set has 316 there against 324 at the other three — and
      # either way the Tailwind plugin emits no rule and the element renders as nothing.
      # Read from the checkout rather than from the built stylesheet, because the
      # stylesheet is an artefact of a task the suite does not run.
      named = named_glyphs()

      assert named != [], "no glyph was found in the source, so this asserts nothing"

      for name <- named do
        {glyph, grid} = grid_of(name)

        assert File.exists?(Path.join([heroicons(), grid, glyph <> ".svg"])),
               "#{name} names #{glyph} at #{grid}, which Heroicons 2.2.0 does not carry"
      end
    end
  end

  describe "A.9.5. A variant set is enumerated and an unmapped one raises" do
    test "every button variant renders, and an unmapped one raises" do
      for variant <- ~w(bare subtle strong solid) do
        assert button(variant) =~ "<button"
      end

      assert_raise KeyError, fn -> button("primary") end
    end

    test "a labelled control is built from the subtle rung and not the solid one" do
      # The measurement behind it: no step of the ramp reaches 4.5:1 against a solid
      # fill's ink in both themes, so a solid fill is a field for a glyph. If `strong`
      # ever gains a solid fill this fails, which is the point.
      assert button("strong") =~ "bg-fill-subtle"
      refute button("strong") =~ "bg-fill-solid"
      assert button("solid") =~ "bg-fill-solid"
    end
  end

  defp heroicons, do: Path.join(File.cwd!(), "deps/heroicons/optimized")

  # Every `hero-…` class the interface names, read from the source that names it, so a
  # glyph added to a template is covered without this test being edited.
  defp named_glyphs do
    Path.join(File.cwd!(), "lib/pluteus_web/**/*.{ex,heex}")
    |> Path.wildcard()
    |> Enum.flat_map(fn file ->
      Regex.scan(~r/"(hero-[a-z0-9-]+)"/, File.read!(file), capture: :all_but_first)
    end)
    |> List.flatten()
    |> Enum.uniq()
  end

  # A.8.2's ladder, read backwards: the suffix names the grid, and its absence names
  # the 24 outline. `-solid` is the one variant that shares the 24 grid, which A.8.2
  # reserves for a filled treatment at 24 px and above.
  defp grid_of("hero-" <> rest) do
    cond do
      String.ends_with?(rest, "-micro") -> {String.trim_trailing(rest, "-micro"), "16/solid"}
      String.ends_with?(rest, "-mini") -> {String.trim_trailing(rest, "-mini"), "20/solid"}
      String.ends_with?(rest, "-solid") -> {String.trim_trailing(rest, "-solid"), "24/solid"}
      true -> {rest, "24/outline"}
    end
  end

  defp icon(assigns) do
    assigns
    |> Map.merge(%{__changed__: nil})
    |> Map.put_new(:size, nil)
    |> Map.put_new(:class, nil)
    |> CoreComponents.icon()
    |> rendered_to_string()
  end

  defp button(variant) do
    assigns = %{variant: variant, __changed__: nil}

    ~H"""
    <CoreComponents.button variant={@variant}>Go</CoreComponents.button>
    """
    |> rendered_to_string()
  end
end
