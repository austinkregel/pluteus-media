defmodule Pluteus.Browse.QueryTest do
  @moduledoc """
  What a browse surface is showing, and how a narrowing is added, removed and linked to
  (spec-10 §9.2, §9.3, §9.4).

  Pure, so it is exercised directly: the catalog decides what a query *holds* and this
  decides what the query *is*, and the second is where a wrong answer would be silent.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Browse.Query
  alias Pluteus.Surfaces.Registry, as: Surfaces

  describe "§9.2. A query is a mode and the facets narrowing it" do
    test "a mode with no parameters narrows nothing" do
      assert {:ok, query} = Query.parse("everything", %{})

      assert query.mode == "everything"
      refute Query.narrowed?(query)
      assert Query.narrowings(query) == []
    end

    test "every mode the registry names can be asked for" do
      for mode <- Surfaces.browse_modes() do
        assert {:ok, %Query{mode: ^mode}} = Query.parse(mode, %{})
      end
    end

    test "a mode outside the registry is refused rather than answered" do
      assert {:error, {:unknown_mode, "shuffle"}} = Query.parse("shuffle", %{})
    end

    test "a parameter naming no axis is not a facet" do
      # A surface's own paging and format parameters reach this in the same map.
      assert {:ok, query} = Query.parse("everything", %{"after" => "x", "_format" => "html"})

      refute Query.narrowed?(query)
    end
  end

  describe "§9.3. Values are disjunctive within an axis and conjunctive across them" do
    test "two values on one axis are both carried" do
      assert {:ok, query} = Query.parse("everything", %{"category" => "photograph,document"})

      assert Enum.sort(Query.on(query, "category")) == ["document", "photograph"]
    end

    test "two axes are carried independently" do
      assert {:ok, query} =
               Query.parse("everything", %{"category" => "photograph", "decade" => "1950"})

      assert Query.on(query, "category") == ["photograph"]
      assert Query.on(query, "decade") == ["1950"]
    end

    test "an axis nothing names carries nothing" do
      assert {:ok, query} = Query.parse("everything", %{"category" => "photograph"})

      for axis <- Surfaces.facets() -- ["category"] do
        assert Query.on(query, axis) == []
      end
    end

    test "a value repeated in a parameter is carried once" do
      assert {:ok, query} = Query.parse("everything", %{"category" => "document,document"})

      assert Query.on(query, "category") == ["document"]
    end

    test "surrounding space and empty values do not make a narrowing" do
      assert {:ok, query} = Query.parse("everything", %{"category" => " document , ,"})

      assert Query.on(query, "category") == ["document"]
    end
  end

  describe "§9.3. A closed vocabulary refuses what it does not hold" do
    test "a category outside the registry is refused" do
      assert {:error, {:unknown_category, "sculpture"}} =
               Query.parse("everything", %{"category" => "sculpture"})
    end

    test "one bad value refuses the request rather than narrowing by the rest" do
      # Narrowing by the half that parsed would answer a question nobody asked.
      assert {:error, {:unknown_category, _one}} =
               Query.parse("everything", %{"category" => "document,sculpture"})
    end

    test "an identifier-valued axis is not bounded by any registry" do
      # No registry knows the household's own people and places. An identifier naming
      # nothing selects nothing, which is an empty surface rather than a bad request.
      id = "01a10000-0000-7000-8000-000000000000"

      assert {:ok, query} = Query.parse("everything", %{"person" => id, "place" => id})

      assert Query.on(query, "person") == [id]
      assert Query.on(query, "place") == [id]
    end
  end

  describe "§9.4. Each narrowing is removable on its own" do
    test "removing one value of an axis keeps the others" do
      {:ok, query} =
        Query.parse("everything", %{"decade" => "1950,1960", "category" => "document"})

      widened = Query.widen(query, "decade", "1950")

      assert Query.on(widened, "decade") == ["1960"]
      assert Query.on(widened, "category") == ["document"]
    end

    test "removing the last value of an axis leaves the axis absent, not empty" do
      {:ok, query} = Query.parse("everything", %{"decade" => "1950"})

      widened = Query.widen(query, "decade", "1950")

      refute Query.narrowed?(widened)
      assert Query.to_params(widened) == %{}
    end

    test "adding a value already carried narrows no further" do
      {:ok, query} = Query.parse("everything", %{"category" => "document"})

      assert Query.narrow(query, "category", "document") == query
    end

    test "adding a value to an axis that carried none narrows by it" do
      {:ok, query} = Query.parse("everything", %{})

      assert Query.on(Query.narrow(query, "decade", "1950"), "decade") == ["1950"]
    end

    test "removing a value nothing carried changes nothing" do
      {:ok, query} = Query.parse("everything", %{"category" => "document"})

      assert Query.widen(query, "decade", "1950") == query
    end
  end

  describe "§9.4. The query is the address" do
    test "parameters round-trip, so a narrowed surface can be linked to" do
      params = %{"category" => "photograph,document", "decade" => "1950"}

      {:ok, query} = Query.parse("everything", params)
      {:ok, again} = Query.parse("everything", Query.to_params(query))

      assert again == query
    end

    test "one query has one address, whatever order its values arrived in" do
      {:ok, one} = Query.parse("everything", %{"category" => "document,photograph"})
      {:ok, other} = Query.parse("everything", %{"category" => "photograph,document"})

      assert Query.to_params(one) == Query.to_params(other)
    end

    test "the chips are rendered in a stable order whatever the parameters' was" do
      {:ok, query} =
        Query.parse("everything", %{"decade" => "1960,1950", "category" => "document"})

      assert Query.narrowings(query) == [
               {"category", "document"},
               {"decade", "1950"},
               {"decade", "1960"}
             ]
    end
  end
end
