defmodule Pluteus.Catalog.PerformanceTest do
  @moduledoc """
  Musical's authored attribute: what kind of recording an expression is (spec-01 §6.5).

  It does the one thing §6.5's attributes do — measure distance from the canonical form —
  so what is asserted is that its values are the registry's and no others, that a person
  can record it without disturbing what else is known, and that a work whose canonical
  recording is the studio one resolves to that recording over a live or a demo one.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Representative
  alias Pluteus.Catalog.Selection
  alias Pluteus.Catalog.WorkTypes
  alias Pluteus.Ingest.Place
  alias Pluteus.Principals

  describe "§6.5. Performance is musical's, and its values are the registry's" do
    test "musical names it beside LRM's two, and says it was authored" do
      assert "performance" in WorkTypes.attributes("musical")
      assert WorkTypes.authored("musical") == ["performance"]
      assert WorkTypes.source("musical") == "LRM-E2-A2"
    end

    test "its vocabulary is closed, and an open attribute has none" do
      assert WorkTypes.vocabulary("performance") == ~w(studio live demo remix alternate)
      assert WorkTypes.vocabulary("key") == nil
    end

    test "a value outside the vocabulary is refused naming it" do
      %{expression: expression} = a_song("Iron Fist")

      assert {:error, changeset} =
               Representative.revise(:expression, expression.id, %{"performance" => "bootleg"})

      assert [message] = errors_on(changeset).significant_attributes
      assert message =~ ~s(gives performance the value "bootleg")
      assert message =~ "studio, live, demo, remix, alternate"
    end

    test "a type that does not name it refuses it" do
      {:ok, %{work: film, expression: cut}} = Catalog.create_work("The Dig")
      {:ok, _} = Catalog.categorize(film.id, Place.category_scheme(), "film", :automatic)

      assert {:error, changeset} =
               Representative.revise(:expression, cut.id, %{"performance" => "live"})

      assert [message] = errors_on(changeset).significant_attributes
      assert message =~ "names performance"
    end
  end

  describe "§6.5. A person records it without disturbing what else is known" do
    test "the attributes named are set and the rest kept", %{} do
      %{expression: expression} = a_song("Iron Fist")

      {:ok, _} = Representative.revise(:expression, expression.id, %{"key" => "E minor"})

      {:ok, revised} =
        Representative.revise(:expression, expression.id, %{"performance" => "demo"})

      assert revised.significant_attributes == %{"key" => "E minor", "performance" => "demo"}
    end

    test "a null removes the one it names" do
      %{expression: expression} = a_song("Iron Fist")

      {:ok, _} =
        Representative.revise(:expression, expression.id, %{
          "key" => "E minor",
          "performance" => "demo"
        })

      {:ok, revised} = Representative.revise(:expression, expression.id, %{"performance" => nil})

      assert revised.significant_attributes == %{"key" => "E minor"}
    end
  end

  describe "§8.6. The studio recording is the one a work resolves to" do
    test "over a live recording and a demo of the same song" do
      {:ok, principal} = Principals.create_principal(%{role: "member"})
      %{work: work, expression: live} = a_song("Iron Fist")
      {:ok, %{expression: demo}} = Catalog.add_expression(work.id, "Iron Fist (demo)")
      {:ok, %{expression: studio}} = Catalog.add_expression(work.id, "Iron Fist")

      {:ok, _} = Representative.revise(:work, work.id, %{"performance" => "studio"})
      {:ok, _} = Representative.revise(:expression, live.id, %{"performance" => "live"})
      {:ok, _} = Representative.revise(:expression, demo.id, %{"performance" => "demo"})
      {:ok, _} = Representative.revise(:expression, studio.id, %{"performance" => "studio"})

      given = Selection.for_principal(work.id, principal.id, %Profile{})

      assert given.expression.id == studio.id
      assert given.by == :nearest
      assert given.alternatives == 2
    end
  end

  defp a_song(name) do
    {:ok, %{work: work} = created} = Catalog.create_work(name)

    {:ok, _} =
      Catalog.categorize(work.id, Place.category_scheme(), "music_recording", :automatic)

    created
  end
end
