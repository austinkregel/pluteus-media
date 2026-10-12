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
  alias Pluteus.Ingest.Credits
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

      {:available, counts} = facets_for(query)["category"]

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

  describe "23. The decade a holding was made in counts the same way" do
    setup do
      issued(work("photograph"), "1959")
      issued(work("photograph"), "1959-08-17")
      issued(work("document"), "1964")

      :ok
    end

    test "a date reaches the decade it falls in, however finely it was stated" do
      assert %{"1950s" => _fifties, "1960s" => _sixties} = decades(%{})
      assert decades(%{})["1950s"] == 2
    end

    test "each count is what selecting that decade leaves held" do
      assert_counts_hold("decade", %{})
      assert_counts_hold("decade", %{"decade" => "1950s"})
    end

    test "narrowing by a decade and a kind is both at once" do
      {:ok, query} = Query.parse("everything", %{"decade" => "1950s", "category" => "document"})

      assert Entries.count(query) == 0
    end

    test "a holding issued in two decades is not counted into the surface twice" do
      # The case the arithmetic has to get right: a work already held under a selected
      # decade must add nothing under another, or the count would promise a holding that
      # selecting it does not gain.
      both = work("scan")
      issued(both, "1959")
      issued(both, "1964")

      assert_counts_hold("decade", %{"decade" => "1950s"})
    end
  end

  describe "23. The people a holding credits count the same way" do
    setup do
      %{
        miles: credited(work("album"), "Miles Davis"),
        bill: credited(work("album"), "Bill Evans")
      }
    end

    test "each person offered is one the catalogue credits", %{miles: miles} do
      {:available, counts} = facet("person", %{})

      assert Enum.any?(counts, &(elem(&1, 0) == miles))
    end

    test "each count is what selecting that person leaves held" do
      assert_counts_hold("person", %{})
    end

    test "a holding credited to two people is not counted into the surface twice",
         %{miles: miles} do
      # A work carries as many credits as it names, so this is the multi-valued case
      # again: already held under one, it must add nothing under the other.
      both = work("album")
      credited(both, "Miles Davis")
      credited(both, "Bill Evans")

      assert_counts_hold("person", %{"person" => miles})
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

      answered = facets_for(query)

      for axis <- Surfaces.facets() do
        assert Map.has_key?(answered, axis), "the #{axis} facet was not named at all"
      end
    end

    test "an axis whose relation is not read yet is inert and says why" do
      {:ok, query} = Query.parse("everything", %{})

      answered = facets_for(query)

      for axis <- Surfaces.facets() -- Entries.narrowable_axes() do
        assert {:inert, reason} = answered[axis]
        assert is_binary(reason) and reason != ""
      end
    end

    test "an inert axis says the holdings do not state it, not that nothing is held" do
      # Reporting an empty facet would say the household holds nothing made anywhere,
      # which is a different and false claim. So the reason's subject is the holdings.
      {:ok, query} = Query.parse("everything", %{})

      for axis <- Surfaces.facets() -- Entries.narrowable_axes() do
        assert {:inert, reason} = facets_for(query)[axis]

        assert reason =~ "None of these",
               "the #{axis} facet gives #{inspect(reason)}, whose subject is not the holdings"
      end
    end
  end

  # Every axis answered for, against how many the query holds as it stands. That figure
  # is taken here rather than read back from the answer, so each count is checked against
  # a total this test derived for itself.
  defp facets_for(query), do: Counts.for_query(query, Entries.count(query))

  # The whole of criterion 23: for every value offered, select it and confirm the
  # surface holds exactly what the count advertised.
  defp assert_counts_hold(params), do: assert_counts_hold("category", params)

  defp assert_counts_hold(axis, params) do
    {:ok, query} = Query.parse("everything", params)
    {:available, counts} = facets_for(query)[axis]

    assert counts != [], "no value was offered, so this asserts nothing"

    for {value, advertised} <- counts do
      held = Entries.count(Query.narrow(query, axis, value))

      assert held == advertised,
             "selecting #{value} left #{held} holdings where the count said #{advertised}"
    end
  end

  defp facet(axis, params) do
    {:ok, query} = Query.parse("everything", params)

    facets_for(query)[axis]
  end

  defp credited(work_id, name) do
    agent = Credits.artist_for(name, nil)

    Credits.record({:work, work_id}, :artist, [{name, nil}])

    agent.id
  end

  defp decades(params) do
    {:ok, query} = Query.parse("everything", params)
    {:available, counts} = facets_for(query)["decade"]

    Map.new(counts)
  end

  defp issued(work_id, date) do
    [expression] = Catalog.expressions_of(work_id)
    [manifestation] = Catalog.manifestations_of(expression.id)

    {:ok, %{res: span}} =
      Catalog.create_named_res(:time_span, %{nomen_string: date, provenance: :automatic})

    {:ok, _} =
      Catalog.associate(manifestation.id, span.id, "time-of-publication-or-manufacture")

    work_id
  end

  defp counts_for(params) do
    {:ok, query} = Query.parse("everything", params)
    {:available, counts} = facets_for(query)["category"]

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
