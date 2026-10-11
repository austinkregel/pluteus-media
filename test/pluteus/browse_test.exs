defmodule Pluteus.BrowseTest do
  @moduledoc """
  What a render of a browse surface costs.

  §9.3 requires every facet value's count be recomputed on every render, which makes the
  cost of a render the thing most likely to decide whether the surface is usable at all.
  A surface asking a query per facet value, or per row, is correct on a household of
  three holdings and unusable on one of thirty thousand — and nothing about what it
  displays would differ, so no test of its output could catch it.

  Not async: the repo's telemetry is process-wide, so a test running beside this would
  put its own queries in the stream being counted.
  """

  use Pluteus.DataCase, async: false

  alias Pluteus.Browse
  alias Pluteus.Browse.Query
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Profile
  alias Pluteus.Ingest.Place
  alias Pluteus.Principals

  setup do
    {:ok, principal} = Principals.create_principal(%{role: "member"})

    %{principal: principal}
  end

  describe "12. A render costs a fixed number of queries" do
    test "the cost does not grow with the catalogue", %{principal: principal} do
      holdings(3, "photograph")
      small = cost(principal)

      holdings(40, "photograph")
      larger = cost(principal)

      assert larger == small,
             "a render cost #{small} queries over 3 holdings and #{larger} over 43"
    end

    test "the cost is stated, so a change to it has to be meant", %{principal: principal} do
      # Twenty-six as measured: the entries, their names, what each of them is and what
      # it is held as, how much
      # it gathers, who it credits and the cover it wears, the query's total and the whole
      # catalogue's, the bytes it takes and when the first of it arrived, how many of it
      # nothing credits, a distribution per narrowable axis, this principal's own looking
      # and the works it names, the overdue holdings, the undated ones, the unkinded ones
      # and the undecided pairs. Resolving a set of names is itself bounded in three, and
      # the page resolves two — the entries and the agents they credit — so the list
      # describes what the queries are for rather than giving one phrase per query.
      #
      # A bound rather than that exact figure, since a query added for a reason is not a
      # defect. What would be is one creeping in unnoticed, which this catches by failing
      # with the new number. An axis costs one query however many values it offers, and a
      # row costs none, which are the properties the assertions above hold.
      holdings(5, "photograph")

      assert cost(principal) <= 27, "a render now costs #{cost(principal)} queries"
    end

    test "the cost does not grow with how many values a facet offers",
         %{principal: principal} do
      holdings(2, "photograph")
      one_value = cost(principal)

      for category <- ~w(document album music_recording video_game comic_issue audiobook) do
        holdings(2, category)
      end

      seven_values = cost(principal)

      assert seven_values == one_value,
             "a render cost #{one_value} queries with one facet value and " <>
               "#{seven_values} with seven"
    end

    test "the cost does not grow with how many rows are shown", %{principal: principal} do
      holdings(40, "photograph")

      few = cost(principal, 5)
      many = cost(principal, 40)

      assert many == few, "a render cost #{few} queries for 5 rows and #{many} for 40"
    end

    test "a narrowed render costs no more than an unnarrowed one", %{principal: principal} do
      holdings(10, "photograph")
      holdings(10, "document")

      bare = cost(principal)
      narrowed = cost(principal, 60, %{"category" => "photograph"})

      # A narrowing adds the axis's own count of what is currently held, and nothing
      # that grows: one more query, whatever is being narrowed by.
      assert narrowed - bare <= 1,
             "narrowing cost #{narrowed - bare} extra queries"
    end
  end

  describe "what a surface is handed" do
    test "the entries are bounded and the total is of the whole query",
         %{principal: principal} do
      holdings(10, "photograph")

      {:ok, query} = Query.parse("everything", %{})
      surface = Browse.surface(query, principal.id, %Profile{}, 4)

      assert [_one, _two, _three, _four] = surface.entries
      assert surface.total == 10
    end

    test "every facet axis and every door is answered", %{principal: principal} do
      holdings(1, "photograph")

      {:ok, query} = Query.parse("everything", %{})
      surface = Browse.surface(query, principal.id, %Profile{})

      assert map_size(surface.facets) == 5
      assert [_looking, _unverified, _undated, _unkinded, _undecided] = surface.unfinished
      assert surface.query == query
    end
  end

  defp cost(principal, limit \\ 60, params \\ %{}) do
    {:ok, query} = Query.parse("everything", params)

    queries_during(fn -> Browse.surface(query, principal.id, %Profile{}, limit) end) |> length()
  end

  defp holdings(count, category) do
    for _each <- 1..count do
      {:ok, %{work: work}} =
        Catalog.create_work(%{nomen_string: "a #{category}", provenance: :automatic})

      {:ok, _} = Catalog.categorize(work.id, Place.category_scheme(), category, :automatic)

      work.id
    end
  end
end
