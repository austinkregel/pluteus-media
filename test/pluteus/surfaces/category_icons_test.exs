defmodule Pluteus.Surfaces.CategoryIconsTest do
  @moduledoc """
  What identifies a category on a surface.

  Three registries have to agree for a category to be drawable: the one that says a
  category may be recorded, the one that says what draws it, and the glyph set on disk.
  A category that reaches a surface with no glyph raises there rather than rendering
  blank, so what is asserted here is that it cannot reach one.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Ingest.Registry
  alias Pluteus.Surfaces.Registry, as: Surfaces
  alias PluteusWeb.Icon

  @classes ~w(video audio image text software package)

  describe "Every category something lists is drawable" do
    test "each drawn category names a glyph the interface may write" do
      for category <- Surfaces.drawn_categories() do
        glyph = Surfaces.category_icon(category).glyph

        assert glyph in Icon.names(),
               "#{category} is drawn with #{glyph}, which the glyph set does not carry"
      end
    end

    test "each drawn category names one of the six broad classes" do
      for category <- Surfaces.drawn_categories() do
        assert Surfaces.category_icon(category).class in @classes
      end
    end

    test "each drawn category carries the word a household uses for it" do
      for category <- Surfaces.drawn_categories() do
        name = Surfaces.category_icon(category).name

        assert is_binary(name) and name != ""

        refute String.contains?(name, "_"),
               "#{category} reaches a surface as #{name}, which is the model's spelling"
      end
    end

    test "every category placement can record is either drawn or a companion" do
      # The gap this closes: a category added to ingest and not here would be listed by
      # the browse surfaces and raise when something tried to draw it.
      companions = Registry.companion_kinds()

      for category <- Registry.recordable_categories(), category not in companions do
        assert category in Surfaces.drawn_categories(),
               "#{category} can be recorded but nothing says what draws it"
      end
    end

    test "a companion is drawn by nothing, because it is never presented as a holding" do
      for companion <- Registry.companion_kinds() do
        refute companion in Surfaces.drawn_categories()

        assert_raise KeyError, fn -> Surfaces.category_icon(companion) end
      end
    end
  end

  describe "The colour groups and the glyph identifies" do
    test "the categories of one class share its colour and differ by glyph" do
      by_class = Enum.group_by(Surfaces.drawn_categories(), &Surfaces.category_icon(&1).class)

      for {_class, [_one, _more | _rest] = categories} <- by_class do
        glyphs = categories |> Enum.map(&Surfaces.category_icon(&1).glyph) |> Enum.uniq()

        assert match?([_one, _more | _rest], glyphs),
               "every category of this class is drawn with the same glyph, " <>
                 "so nothing but colour tells them apart"
      end
    end
  end
end
