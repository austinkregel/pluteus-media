defmodule PluteusWeb.BrowseLiveTest do
  @moduledoc """
  The first rendered browse mode (spec-10 §9.2, §9.3, §14.1, §17.3).

  The surface's own arithmetic is asserted in `Pluteus.BrowseTest` and the modules under
  it. What is asserted here is what a person is actually shown: that the counts reach the
  page, that an axis which cannot answer says why rather than appearing empty, that the
  modes without a surface cannot be followed, and that nothing reachable in the rail is
  unreachable at phone width.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Dedup
  alias Pluteus.Ingest.Place
  alias Pluteus.Principals
  alias PluteusWeb.Chrome

  setup %{conn: conn} do
    %{conn: conn |> through_proxy(a_subject()) |> on_a_surface()}
  end

  describe "§9.2. The gateway renders what the catalogue holds" do
    test "every kind the catalogue holds is a door carrying its count", %{conn: conn} do
      for _each <- 1..3, do: holding("photograph")
      holding("document")

      {:ok, _live, html} = live(conn, ~p"/everything")

      assert html =~ "Photograph"
      assert html =~ "Document"
      assert html =~ "4 holdings"
    end

    test "a door leads to the narrowing it counts", %{conn: conn} do
      holding("photograph")

      {:ok, _live, html} = live(conn, ~p"/everything")

      assert html =~ "/everything?category=photograph"
    end

    # §9.5 has a surface say which order it is in, and it says it of the search surface:
    # a result carries no figure, so an unexplained order there reads as a ranking nobody
    # can check. A door band is ordered too, and every door prints the count it is ordered
    # on, so what the order is made of is readable from the doors themselves.
    test "the doors stand in the order of the counts they carry", %{conn: conn} do
      for _each <- 1..3, do: holding("photograph")
      holding("document")

      {:ok, _live, html} = live(conn, ~p"/everything")

      {photographs, _length} = :binary.match(html, "/everything?category=photograph")
      {documents, _length} = :binary.match(html, "/everything?category=document")

      assert photographs < documents
    end

    test "an empty catalogue says so rather than drawing an empty band", %{conn: conn} do
      # Every band, not one: a band that drops its empty rendering draws a heading over
      # nothing, which reads as a surface still loading rather than one with no answer.
      {:ok, _live, html} = live(conn, ~p"/everything")

      assert html =~ "Nothing is held, so there are no kinds to go by."
      assert html =~ "Nothing here states when it was made."
      assert html =~ "Nothing here credits anybody."
    end

    test "a narrowing is carried in the address and the surface follows it", %{conn: conn} do
      for _each <- 1..2, do: holding("photograph")
      holding("document")

      {:ok, _live, html} = live(conn, ~p"/everything?category=photograph")

      assert html =~ "of 3 holdings"
      assert html =~ "Narrowed by"
    end

    # §12.1 gives each category one primary surface, and only three of them run a medium
    # against a clock. A document is read, so a control offering to start it is offering
    # something that does not exist.
    test "a row offers to play what is played, and nothing for what is read",
         %{conn: conn} do
      music = named("a song", "music_recording")
      document = named("a letter", "document")

      {:ok, live, _html} = live(conn, ~p"/everything?category=music_recording")
      assert has_element?(live, ~s|button[phx-click="play"][phx-value-res="#{music}"]|)

      {:ok, live, _html} = live(conn, ~p"/everything?category=document")
      refute has_element?(live, ~s|button[phx-click="play"]|)
      refute has_element?(live, ~s|button[phx-value-res="#{document}"]|)
    end

    test "an axis nothing narrows by is answered, not crashed into", %{conn: conn} do
      # A surface that raised here would take the page down, and the client recovers
      # from that by reloading onto the same address.
      holding("photograph")

      {:ok, _live, html} = live(conn, ~p"/everything?language=en")

      assert html =~ "This cannot be gone through by language."
    end

    test "a kind the registry does not name is refused, not answered", %{conn: conn} do
      holding("photograph")

      {:ok, _live, html} = live(conn, ~p"/everything?category=sculpture")

      assert html =~ "nothing here of a kind called sculpture"
    end
  end

  describe "Narrowing: the values recede, the rows take over, the choice becomes a chip" do
    test "the doors give way to rows naming each holding", %{conn: conn} do
      named("A letter home", "document")

      {:ok, _live, html} = live(conn, ~p"/everything?category=document")

      assert html =~ "A letter home"
      refute html =~ "Unfinished"
    end

    test "each narrowing is a chip in the rail", %{conn: conn} do
      holding("document")

      {:ok, _live, html} = live(conn, ~p"/everything?category=document")

      assert html =~ "Narrowed by"
      assert html =~ "Remove the facet Document"
    end

    test "a chip removes its own value and leaves the others", %{conn: conn} do
      holding("document")
      holding("photograph")

      {:ok, _live, html} = live(conn, ~p"/everything?category=document,photograph")

      # Removing one value must leave the other narrowing in place, not drop the axis.
      assert html =~ "/everything?category=photograph"
      assert html =~ "/everything?category=document"
    end

    test "removing the last narrowing leads back to the unnarrowed mode", %{conn: conn} do
      holding("document")

      {:ok, _live, html} = live(conn, ~p"/everything?category=document")

      assert html =~ ~s|href="/everything"|
    end

    test "a narrowing holding nothing says so and says how to widen it", %{conn: conn} do
      holding("document")

      {:ok, _live, html} = live(conn, ~p"/everything?category=album")

      assert html =~ "Nothing is held that is all of these at once"
    end

    test "a row whose kind nothing records says so where the kind would have gone",
         %{conn: conn} do
      # Rendering nothing there is the failure §5.3 names: a second line left blank is
      # indistinguishable from one that did not render. The row is reached by decade,
      # because a kind nothing recorded is a value no narrowing can name.
      dated(named("Blade Runner, commentary", nil), "1982")

      {:ok, _live, html} = live(conn, ~p"/everything?decade=1980s")

      assert html =~ "Blade Runner, commentary"
      assert html =~ "not yet examined"
    end

    test "the unnarrowed surface carries no chips", %{conn: conn} do
      holding("document")

      {:ok, _live, html} = live(conn, ~p"/everything")

      refute html =~ "Narrowed by"
      assert html =~ "Unfinished"
    end
  end

  describe "§14.3. The door about looking carries no figure" do
    test "it is shown and states no number", %{conn: conn} do
      holding("photograph")

      {:ok, _live, html} = live(conn, ~p"/everything")

      assert html =~ "Nothing you have looked at"
    end
  end

  describe "§17.3. A door renders as whatever is actually behind it" do
    test "one with somewhere to go and something behind it is a link", %{conn: conn} do
      an_open_candidate()

      {:ok, live, _html} = live(conn, ~p"/everything")

      assert has_element?(live, ~s|a[href="/findings"]|, "Needs a decision")
    end

    test "one with somewhere to go and nothing behind it is disabled and says why",
         %{conn: conn} do
      # The defect this exists to prevent: the door knows there is nothing behind it and
      # renders a live link onto an empty surface anyway, which is a control for an
      # affordance that does not exist.
      {:ok, live, _html} = live(conn, ~p"/everything")

      assert has_element?(live, "button[disabled]", "Needs a decision")
      refute has_element?(live, ~s|a[href="/findings"]|, "Needs a decision")
    end

    test "one with something behind it and nowhere to go says that instead", %{conn: conn} do
      holding("photograph")

      {:ok, _live, html} = live(conn, ~p"/everything")

      assert html =~ "No date recorded has no surface to open onto."
    end

    test "each shut door states the absence its own figure measures", %{conn: conn} do
      # Four doors shut for four reasons. A single reason would tell three of them wrong.
      {:ok, _live, html} = live(conn, ~p"/everything")

      assert html =~ "There is nothing here you have not looked at."
      assert html =~ "Nothing is overdue for verification."
      assert html =~ "Everything held states when it was made."
      assert html =~ "No pair is waiting on a decision."
    end
  end

  describe "§9.3, §17.3. An axis that cannot answer is named and says why" do
    test "each inert axis is named with its own reason", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/everything")

      assert html =~ "gazetteer"
      assert html =~ "Languages"
    end

    test "an axis that can answer opens a band of its own", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/everything")

      assert html =~ "By when it was made"
      assert html =~ "By who and where"
    end

    test "the place that cannot be answered is said beside the people that can",
         %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/everything")

      assert html =~ "Places: answering where a holding was made"
    end

    test "the place axis does not claim the household holds nothing", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/everything")

      refute html =~ "no places"
    end
  end

  describe "§9.2. A mode with no surface cannot be followed, and one with a surface can" do
    test "the mode with a surface is a link and the rest are disabled", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/everything")

      assert html =~ ~s|href="/everything"|
      assert html =~ "This deployment serves no surface for it."
    end

    test "every mode with an address is reachable at phone width too", %{conn: conn} do
      # §9.2: nothing is reachable in the rail and not in the tab bar. Four tabs fit
      # across a phone and there are seven modes, so this is what stops a mode gaining a
      # surface and quietly becoming unreachable below the rail's breakpoint.
      with_a_surface = for {slug, _n, _g, _w, at} <- Chrome.modes(), at, do: slug
      in_the_tab_bar = for {slug, _n, _g, _w, _at} <- Chrome.tabs(), do: slug

      for slug <- with_a_surface do
        assert slug in in_the_tab_bar,
               "#{slug} has a surface but no tab, so it cannot be reached on a phone"
      end

      assert {:ok, _live, _html} = live(conn, ~p"/everything")
    end
  end

  describe "§4.4, spec-07 §3.4. A surface is the requesting principal's own, and declared" do
    test "a request carrying no principal is refused rather than rendered" do
      refused = get(build_conn() |> on_a_surface(), ~p"/everything")

      assert refused.status in 401..403
    end

    test "a device that has declared no surface is asked before anything renders" do
      # §4.4: "the deployment asks before it renders. It does not choose." So an
      # undeclared device gets the question, carrying where it was going.
      asked = get(through_proxy(build_conn(), a_subject()), ~p"/everything")

      assert redirected_to(asked) =~ "/surface"
      assert redirected_to(asked) =~ "everything"
    end
  end

  defp holding(category), do: named("a #{category}", category)

  # Who raised the pair is immaterial to the door, which counts every pair still open,
  # so this takes a principal of its own rather than the one the proxy vouched for.
  defp an_open_candidate do
    {:ok, principal} = Principals.create_principal(%{role: "member"})

    {:ok, candidate} =
      Dedup.propose(
        named("a letter", "document"),
        named("the same letter", "document"),
        principal.id
      )

    candidate
  end

  # A nil category is what ingest leaves behind for a commentary stream: a work of its
  # own embodied in the film's manifestation, which nothing categorizes.
  defp named(name, category) do
    {:ok, %{work: work}} =
      Catalog.create_work(%{nomen_string: name, provenance: :automatic})

    if category,
      do: {:ok, _} = Catalog.categorize(work.id, Place.category_scheme(), category, :automatic)

    work.id
  end

  defp dated(work_id, date) do
    [expression | _rest] = Catalog.expressions_of(work_id)
    [manifestation | _more] = Catalog.manifestations_of(expression.id)

    {:ok, %{res: span}} =
      Catalog.create_named_res(:time_span, %{nomen_string: date, provenance: :automatic})

    {:ok, _} = Catalog.associate(manifestation.id, span.id, "time-of-publication-or-manufacture")

    work_id
  end
end
