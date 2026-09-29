defmodule Pluteus.Catalog.WorkTypesTest do
  @moduledoc """
  spec-01 §6.5 and §17: which attributes are significant per category of work.

  §17 names this registry as seed data and §6.5 carries its table. What is asserted here is
  that the table is the spec's, that every category placement can record has a type, and
  that a type or a category the registry omits raises rather than yielding a distance
  computed over nothing.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Catalog.WorkTypes
  alias Pluteus.Continuity
  alias Pluteus.Ingest.Place
  alias Pluteus.Presentation

  describe "§6.5's table is the registry's" do
    test "LRM supplies five rows and the attributes it names" do
      assert WorkTypes.attributes("textual") == ~w(language intended_audience)
      assert WorkTypes.attributes("musical") == ~w(key medium_of_performance)
      assert WorkTypes.attributes("cartographic") == ~w(cartographic_scale projection)
      assert WorkTypes.attributes("moving_image") == ~w(aspect_ratio colourization)
      assert WorkTypes.attributes("art") == ~w(medium_of_execution)

      for type <- ~w(textual musical cartographic moving_image art) do
        assert WorkTypes.source(type) == "LRM-E2-A2"
      end
    end

    test "every other row says it was authored here" do
      for type <- WorkTypes.all() -- ~w(textual musical cartographic moving_image art) do
        assert WorkTypes.source(type) == "authored",
               "#{type} has no LRM analogue and must say so"
      end
    end

    test "a type the registry does not name raises" do
      assert_raise KeyError, fn -> WorkTypes.attributes("interpretive_dance") end
    end

    test "no type is significant in nothing" do
      for type <- WorkTypes.all() do
        assert WorkTypes.attributes(type) != []
      end
    end
  end

  describe "every category of work has a type" do
    test "the categories mapped are the categories the deployment records" do
      # The category vocabulary lives in the registries placement and presentation read, so
      # a category added there and not here would order its expressions by nothing.
      assert WorkTypes.categories() == Enum.sort(Continuity.Registry.categories())

      # Presentation names only the categories it reserves a box for, so it is a subset: a
      # cue sheet has no aspect ratio and is a category all the same.
      for category <- Presentation.Registry.categories_with_ratio() do
        assert category in WorkTypes.categories()
      end
    end

    test "every mapped category names a type the registry holds" do
      for category <- WorkTypes.categories() do
        assert WorkTypes.of_category(category) in WorkTypes.all()
      end
    end

    test "a category the registry does not map raises" do
      assert_raise KeyError, fn -> WorkTypes.of_category("interpretive_dance") end
    end

    test "a narration is textual, because the work is the text" do
      # spec-04 §6.9 makes a narration an expression of the text with the narrator credited
      # on the expression, so two narrations differ by language and intended audience.
      assert WorkTypes.of_category("audiobook") == "textual"
      assert WorkTypes.of_category("podcast_episode") == "textual"
    end

    test "the two authored rows carry attributes borrowed rather than invented" do
      # A comic's expressions differ as translations and as colourised reprints; a game's as
      # a port and a revision.
      assert WorkTypes.of_category("comic_issue") == "graphic_narrative"
      assert WorkTypes.attributes("graphic_narrative") == ~w(language colourization)

      assert WorkTypes.of_category("video_game") == "software"
      assert WorkTypes.attributes("software") == ~w(platform revision)
    end

    test "three types no category yields are reached only by correction" do
      # §6.5 authored personal record for a relative's letters, which no ingest path
      # produces, and LRM's cartographic and art rows have no category either.
      unplaced = WorkTypes.all() -- Enum.map(WorkTypes.categories(), &WorkTypes.of_category/1)

      assert Enum.sort(unplaced) == ~w(art cartographic personal_record)
    end
  end

  describe "the scheme is its own" do
    test "a work's type is recorded under a scheme of its own" do
      # [ANNEX-A] §A.9 reads LRM §4.2.3 as permitting several independent schemes at once,
      # so the type does not displace the category placement records.
      refute WorkTypes.scheme() == Place.category_scheme()
    end
  end
end
