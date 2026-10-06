defmodule Pluteus.Browse.CountsTest do
  @moduledoc """
  Criterion 23: every facet value carries a count computed against the current query.

  Every count here is checked against what selecting it actually leaves the surface
  holding, rather than against a number written into the test. A count compared to a
  fixture asserts that the arithmetic has not changed; a count compared to its own
  consequence asserts the thing §9.3 asks for, which is that the number is not a false
  statement about what selecting it will do.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Browse.Counts
  alias Pluteus.Browse.Entries
  alias Pluteus.Browse.Query
  alias Pluteus.Catalog
  alias Pluteus.Ingest.Place
  alias Pluteus.Surfaces.Registry, as: Surfaces

  setup do
    for _each <- 1..3, do: work("photograph")
    for _each <- 1..2, do: work("document")
    work("album")

    :ok
  end

  describe "23. Every facet value's count is what selecting it will leave held" do
    test "with nothing selected, each count is what selecting it gives" do
      assert_counts_hold(%{})
    end

    test "with a value selected on the same axis, each count is still what it gives" do
      # The case the arithmetic is most likely to get wrong: selecting a second value on
      # an axis widens it, so the count must exceed what is currently held rather than
      # narrow it.
      assert_counts_hold(%{"category" => "photograph"})
    end

    test "with two values selected, each count is still what it gives" do
      assert_counts_hold(%{"category" => "photograph,document"})
    end

    test "selecting a value already selected changes nothing, and the count says so" do
      {:ok, query} = Query.parse("everything", %{"category" => "photograph"})

      {:available, counts} = Counts.for_query(query)["category"]

      assert {"photograph", count} = Enum.find(counts, &(elem(&1, 0) == "photograph"))
      assert count == Entries.count(query)
    end

    test "a value on another axis is unaffected by what this axis carries" do
      # Conjunctive across axes: narrowing by category must not change what the
      # category axis offers for a value it does not carry.
      bare = counts_for(%{})
      narrowed = counts_for(%{"category" => "photograph"})

      assert bare["album"] == 1
      assert narrowed["album"] == Entries.count(elem(parse(%{"category" => "photograph"}), 1)) + 1
    end
  end

  describe "23. A count is of the current query, not of the catalog" do
    test "a count drops when something else narrows the surface away" do
      before = counts_for(%{})

      {:ok, _} = Catalog.correct_category(hd(ids("photograph")), Place.category_scheme(), "album")

      after_correction = counts_for(%{})

      assert after_correction["photograph"] == before["photograph"] - 1
      assert after_correction["album"] == before["album"] + 1
    end

    test "a category nothing carries is not offered" do
      refute Map.has_key?(counts_for(%{}), "video_game")
    end
  end

  describe "§9.3. A facet with no available values is named and inert" do
    test "every axis the registry names is answered for" do
      {:ok, query} = Query.parse("everything", %{})

      answered = Counts.for_query(query)

      for axis <- Surfaces.facets() do
        assert Map.has_key?(answered, axis), "the #{axis} facet was not named at all"
      end
    end

    test "an axis whose relation is not read yet is inert and says why" do
      {:ok, query} = Query.parse("everything", %{})

      answered = Counts.for_query(query)

      for axis <- Surfaces.facets() -- Entries.narrowable_axes() do
        assert {:inert, reason} = answered[axis]
        assert is_binary(reason) and reason != ""
      end
    end

    test "the place facet says it is the gazetteer it wants, not that nothing is held" do
      # Reporting an empty facet would say the household holds nothing made anywhere.
      {:ok, query} = Query.parse("everything", %{})

      assert {:inert, reason} = Counts.for_query(query)["place"]
      assert reason =~ "gazetteer"
    end
  end

  # The whole of criterion 23: for every value offered, select it and confirm the
  # surface holds exactly what the count advertised.
  defp assert_counts_hold(params) do
    {:ok, query} = Query.parse("everything", params)
    {:available, counts} = Counts.for_query(query)["category"]

    assert counts != [], "no value was offered, so this asserts nothing"

    for {value, advertised} <- counts do
      held = Entries.count(Query.narrow(query, "category", value))

      assert held == advertised,
             "selecting #{value} left #{held} holdings where the count said #{advertised}"
    end
  end

  defp counts_for(params) do
    {:ok, query} = Query.parse("everything", params)
    {:available, counts} = Counts.for_query(query)["category"]

    Map.new(counts)
  end

  defp parse(params), do: Query.parse("everything", params)

  defp ids(category) do
    {:ok, query} = Query.parse("everything", %{"category" => category})

    Entries.ids(query, 100)
  end

  defp work(category) do
    {:ok, %{work: work}} =
      Catalog.create_work(%{nomen_string: "a #{category}", provenance: :automatic})

    {:ok, _} = Catalog.categorize(work.id, Place.category_scheme(), category, :automatic)

    work.id
  end
end
