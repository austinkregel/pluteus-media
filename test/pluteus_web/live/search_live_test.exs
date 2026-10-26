defmodule PluteusWeb.SearchLiveTest do
  @moduledoc """
  The search surface as a person meets it ([spec-10] §9.5, criteria 13, 14 and 52).

  What a search reaches and in what order is asserted in `Pluteus.Browse.SearchTest`.
  What is asserted here is the surface: that it is reached from every mode with the facet
  set intact, that it is a page of its own, and that each row says what §6.2 says it must.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Ingest.Place

  setup %{conn: conn} do
    %{conn: conn |> through_proxy(a_subject()) |> on_a_surface()}
  end

  # Criterion 52: "Browsing and searching do not share a results page, and reaching search
  # from a mode does not discard the active facet set."
  describe "52. Search is a page of its own, reached with the facet set intact" do
    test "searching from a narrowed mode carries the mode and its facets", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/sets?#{[category: "album"]}")

      assert {:error, {:live_redirect, %{to: to}}} =
               live |> form("#rail-search-form", %{q: "blue"}) |> render_submit()

      %URI{path: path, query: query} = URI.parse(to)

      assert path == "/search"
      assert URI.decode_query(query) == %{"q" => "blue", "in" => "sets", "category" => "album"}
    end

    test "every surface's field reaches search, an entity page's included", %{conn: conn} do
      work = named("Ivanhoe #{unique()}", "ebook")

      {:ok, live, _html} =
        conn |> put_req_header("accept", "text/html") |> live(~p"/works/#{work}")

      assert {:error, {:live_redirect, %{to: "/search?q=ivanhoe"}}} =
               live |> form("#rail-search-form", %{q: "ivanhoe"}) |> render_submit()
    end

    test "a browse address carrying a term is still a browse surface", %{conn: conn} do
      named("Rob Roy #{unique()}", "ebook")

      {:ok, _live, html} = live(conn, ~p"/everything?#{[q: "rob roy"]}")

      refute html =~ "Searched for"
      refute html =~ ~s(id="search-results")
    end

    test "below the rail's breakpoint the top bar reaches it, with the facets",
         %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/everything?#{[category: "ebook"]}")

      assert has_element?(live, ~s(#top-bar-search[href="/search?category=ebook"]))
    end
  end

  describe "§9.5. The term is one more narrowing, carried with the rest" do
    test "it is a chip, and removing it returns to the mode with the facets on",
         %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/search?#{[q: "blue", in: "sets", category: "album"]}")

      assert has_element?(live, "#narrowed-term", "blue")
      assert has_element?(live, ~s(#narrowed-term[href="/sets?category=album"]))
      # A facet removed from a search stays on the search, keeping the term and the mode.
      assert has_element?(live, ~s(#narrowed-category-album[href="/search?in=sets&q=blue"]))
    end

    test "the field shows the term searched for", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/search?#{[q: "blue"]}")

      assert has_element?(live, ~s(#rail-search[value="blue"]))
    end

    test "with nothing typed yet, the surface offers the field rather than a list",
         %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/search")

      assert has_element?(live, "#search h1", "Search")
      refute has_element?(live, "#search-results")
    end
  end

  describe "§9.5. The surface says which order its results are in" do
    test "by name, where nothing records another", %{conn: conn} do
      suffix = unique()
      named("Kenilworth #{suffix}", "ebook")

      {:ok, live, _html} = live(conn, ~p"/search?#{[q: suffix]}")

      assert has_element?(live, "#search-standing", "in order of their names")
    end
  end

  describe "13. A result reached through another name says which name it was" do
    test "the row states the name that matched", %{conn: conn} do
      title = "Le Rouge et le Noir #{unique()}"
      book = named(title, "ebook")
      # As placement records one, so the title it was placed under is still the one shown.
      {:ok, _} =
        Catalog.create_nomen(%{
          res_id: book,
          nomen_string: "The Red and the Black",
          provenance: :automatic
        })

      {:ok, live, _html} = live(conn, ~p"/search?#{[q: "red and the black"]}")

      assert has_element?(live, "#row-#{book}", title)
      assert has_element?(live, "#row-#{book}", "Matched “The Red and the Black”")
    end

    test "a row found by the name it shows says nothing more", %{conn: conn} do
      book = named("Waverley #{unique()}", "ebook")

      {:ok, live, _html} = live(conn, ~p"/search?#{[q: "waverley"]}")

      assert has_element?(live, "#row-#{book}")
      refute has_element?(live, "#row-#{book}", "Matched")
    end
  end

  describe "14. Results shown by one name are each told apart" do
    test "on the search surface", %{conn: conn} do
      name = "Ivanhoe #{unique()}"
      book = named(name, "ebook")
      film = named(name, "film")

      {:ok, live, _html} = live(conn, ~p"/search?#{[q: name]}")

      assert has_element?(live, "#row-#{book}", "(an ebook)")
      assert has_element?(live, "#row-#{film}", "(a film)")
    end

    test "and on a browse surface's rows", %{conn: conn} do
      name = "Quentin Durward #{unique()}"
      one = named(name, "ebook")
      two = named(name, "ebook")

      {:ok, live, _html} = live(conn, ~p"/everything?#{[category: "ebook"]}")

      assert has_element?(live, "#row-#{one}", "nothing recorded tells these 2 apart")
      assert has_element?(live, "#row-#{two}", "nothing recorded tells these 2 apart")
    end
  end

  defp named(name, category) do
    {:ok, %{work: work}} = Catalog.create_work(%{nomen_string: name, provenance: :automatic})
    {:ok, _} = Catalog.categorize(work.id, Place.category_scheme(), category, :automatic)

    work.id
  end

  defp unique, do: "n#{System.unique_integer([:positive])}"
end
