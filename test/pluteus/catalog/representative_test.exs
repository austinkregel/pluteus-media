defmodule Pluteus.Catalog.RepresentativeTest do
  @moduledoc """
  spec-01 §6.5: what a work is taken to be inherently, what an expression is, and the
  promotion LRM §5.6 grounds.

  The attributes order competing expressions and do nothing else, so what is asserted here
  is that an attribute the work's type does not name cannot be stored, and that the
  promotion's condition is checked rather than assumed.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Representative
  alias Pluteus.Ingest.Place

  defp a_film do
    {:ok, %{work: work, expression: expression, manifestation: manifestation}} =
      Catalog.create_work("The Dig")

    {:ok, _category} = Catalog.categorize(work.id, Place.category_scheme(), "film", :automatic)

    %{work: work, expression: expression, manifestation: manifestation}
  end

  describe "a work's type decides what is significant" do
    test "a film is a moving image, and its attributes are the registry's" do
      %{work: work} = a_film()

      assert Representative.type_of(work.id) == "moving_image"
      assert Representative.significant(work.id) == ~w(aspect_ratio colourization)
    end

    test "a work placement has not categorized has no type and nothing significant" do
      {:ok, %{work: work}} = Catalog.create_work("Untitled")

      assert Representative.type_of(work.id) == nil
      assert Representative.significant(work.id) == []
    end
  end

  describe "an attribute outside the type's set is refused" do
    test "a key the type does not name is named back", %{} do
      %{work: work, expression: expression} = a_film()

      assert {:error, changeset} =
               Representative.describe(expression.id, %{"key" => "D minor"})

      assert ["names key, which this work's type does not"] =
               errors_on(changeset).significant_attributes

      refute work == nil
    end

    test "a work with no category admits no attribute at all" do
      {:ok, %{expression: expression}} = Catalog.create_work("Untitled")

      assert {:error, _changeset} =
               Representative.describe(expression.id, %{"aspect_ratio" => 1.78})
    end

    test "a key the type names is taken" do
      %{expression: expression} = a_film()

      assert {:ok, saved} = Representative.describe(expression.id, %{"aspect_ratio" => 1.78})
      assert saved.significant_attributes == %{"aspect_ratio" => 1.78}
    end
  end

  describe "§6.5's promotion, and where it stops" do
    test "one expression in one manifestation promotes to the work" do
      %{work: work, expression: expression} = a_film()
      {:ok, _described} = Representative.describe(expression.id, %{"aspect_ratio" => 1.78})

      assert Representative.promote(work.id) == :promoted

      assert Repo.get!(Catalog.Work, work.id).representative_attributes == %{
               "aspect_ratio" => 1.78
             }
    end

    test "a second expression stops it" do
      # A container carrying two audio languages is placed like this, so the commonest
      # multi-expression holding a household has is one the promotion must not touch.
      %{work: work, expression: expression, manifestation: manifestation} = a_film()
      {:ok, _described} = Representative.describe(expression.id, %{"aspect_ratio" => 1.78})

      {:ok, _second} =
        Catalog.add_expression_embodied_in(work.id, manifestation.id, "The Dig, in German")

      assert Representative.promote(work.id) == {:not_promoted, :several_expressions}
      assert Repo.get!(Catalog.Work, work.id).representative_attributes == %{}
    end

    test "a second manifestation stops it" do
      %{work: work, expression: expression} = a_film()
      {:ok, _described} = Representative.describe(expression.id, %{"aspect_ratio" => 1.78})

      {:ok, _second} = Catalog.add_manifestation(expression.id, "A remaster")

      assert Representative.promote(work.id) == {:not_promoted, :several_manifestations}
    end

    test "an expression carrying nothing promotes nothing" do
      %{work: work} = a_film()

      assert Representative.promote(work.id) == {:not_promoted, :nothing_to_promote}
    end
  end
end
