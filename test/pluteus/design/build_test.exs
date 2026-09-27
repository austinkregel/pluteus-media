defmodule Pluteus.Design.BuildTest do
  @moduledoc """
  Annex A.10: what the generated stylesheet must be shaped like for a context to do
  anything at all.

  A.10.1 names its own failure mode — "the context attribute does nothing, with no
  error" — which is precisely the kind that no amount of looking at a screen finds.
  So the layers, their order, and the `inline` keyword are asserted rather than
  eyeballed.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Design.Build
  alias Pluteus.Design.Tokens

  setup_all do
    %{css: Build.stylesheet()}
  end

  describe "A.10.1. Three layers, in this order" do
    test "primitives in the theme layer, semantics outside it, then registrations", %{css: css} do
      theme = index(css, "@theme {")
      root = index(css, ":root {")
      inline = index(css, "@theme inline {")

      assert theme < root, "primitives must be declared before the roles that reference them"
      assert root < inline, "a registration must follow the runtime variable it points at"
    end

    test "layer 3 carries the inline keyword", %{css: css} do
      # Without it the build copies the value at compile time and layer 2's rebinding
      # silently has no effect. This is the assertion that the mechanism exists at all.
      assert css =~ "@theme inline {"
      assert css =~ "--color-surface-raised: var(--sys-color-surface-raised);"
      assert css =~ "--spacing: var(--sys-spacing-base);"
    end

    test "every semantic colour role is registered into Tailwind's namespace", %{css: css} do
      # A.1.4 confines templates to `sys`, and a role with no utility is a role a
      # template cannot use — so each one is registered, and the count is asserted so
      # that adding a role without registering it fails here.
      roles =
        Tokens.all()
        |> Map.keys()
        |> Enum.filter(&String.starts_with?(&1, "sys.color."))

      for role <- roles do
        registered = role |> String.replace_prefix("sys.color.", "") |> String.replace(".", "-")
        runtime = role |> String.replace_prefix("sys.", "sys-") |> String.replace(".", "-")

        assert css =~ "--color-#{registered}: var(--#{runtime});",
               "#{role} is not registered in the theme layer"
      end
    end

    test "a colour carries its sRGB fallback before its OKLCH", %{css: css} do
      # A.2.1 requires both be authored and forbids the build computing either. In CSS
      # that is two declarations, the fallback first, so a renderer that cannot read
      # OKLCH keeps the one it can.
      assert css =~ "--color-grey-01: #101113;\n  --color-grey-01: oklch(0.178 0.004 264);"
    end
  end

  describe "A.10.1. A context is an attribute on the document root" do
    test "every overriding context emits a scope, and no default does", %{css: css} do
      for {modifier, context} <- Tokens.overrides() do
        assert css =~ ~s(:root[data-#{modifier}="#{context}"] {),
               "#{modifier}/#{context} overrides tokens but emits no scope"
      end

      for default <- ~w(dark normal near comfortable full) do
        refute css =~ ~s("#{default}"] {),
               "#{default} is a default and needs no scope of its own"
      end
    end

    test "density rebinds the spacing base, which is what moves the whole scale",
         %{css: css} do
      # A.4.1's "a density change is one number", end to end: compact rebinds the
      # primitive, the primitive feeds --sys-spacing-base, and that feeds Tailwind's
      # --spacing. Asserted as a chain because breaking any link leaves the attribute
      # doing nothing.
      assert css =~ ~s(:root[data-density="compact"] {)
      assert css =~ "--spacing-050: 0.1875rem;"
      assert css =~ "--sys-spacing-base: var(--spacing-050);"
      assert css =~ "--spacing: var(--sys-spacing-base);"
    end

    test "distance changes the root size and nothing else has to follow it",
         %{css: css} do
      # A.3.3's strategy: one number, and every rem moves with it. The type scale, the
      # target floors, the radii and the focus width are all authored in rem, so none
      # of them appears in the far scope.
      assert css =~ "--root-size: 16px;"
      assert css =~ "font-size: var(--root-size);"

      far = scope(css, ~s(:root[data-distance="far"]))

      assert far =~ "--root-size: 32px;"
      refute far =~ "--sys-type-"
      refute far =~ "--sys-size-target"
    end

    test "theme rebinds primitives and contrast rebinds roles", %{css: css} do
      # The two do different things on purpose, and resolving contrast after theme is
      # what lets `more` pick a further step of whichever ramp theme chose.
      light = scope(css, ~s(:root[data-theme="light"]))
      more = scope(css, ~s(:root[data-contrast="more"]))

      assert light =~ "--color-grey-01:"
      refute light =~ "--sys-color-"

      assert more =~ "--sys-color-on-surface-muted: var(--color-grey-12);"
      refute more =~ "--color-grey-01:"
    end
  end

  describe "A.10.2. Breakpoints are literal" do
    test "the four near breakpoints are declared, and far has none", %{css: css} do
      # A custom property is not a legal value in a media query condition, and a
      # root-size change cannot move a rem breakpoint under any arrangement — which is
      # why `far` has no breakpoints rather than doubled ones.
      for {name, at} <- [{"sm", "40rem"}, {"md", "48rem"}, {"lg", "64rem"}, {"xl", "80rem"}] do
        assert css =~ "--breakpoint-#{name}: #{at};"
      end

      refute scope(css, ~s(:root[data-distance="far"])) =~ "--breakpoint"
    end
  end

  defp index(css, needle) do
    [before | _rest] = String.split(css, needle, parts: 2)
    byte_size(before)
  end

  defp scope(css, selector) do
    [_before, rest] = String.split(css, selector <> " {", parts: 2)
    [inside | _after] = String.split(rest, "\n}", parts: 2)
    inside
  end
end
