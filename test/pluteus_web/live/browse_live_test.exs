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
  alias Pluteus.MusicFixtures
  alias Pluteus.Principals
  alias Pluteus.Surfaces.Registry, as: Surfaces
  alias PluteusWeb.Chrome

  setup %{conn: conn} do
    %{conn: conn |> through_proxy(a_subject()) |> on_a_surface()}
  end

  describe "§12.3. Reaching a holding does not tear down what is playing" do
    # The player is a sticky child of the chrome, which survives a live navigation and
    # nothing else. So a row leading to a holding by a page load would stop the music, and
    # whether it does is a property of the link rather than of anything observable on the
    # page it lands on — which is why it is asserted on the link.
    test "a row reaches its holding by live navigation", %{conn: conn} do
      work = holding("document")

      {:ok, live, _html} = live(conn, ~p"/everything?#{[category: "document"]}")

      assert {:error, {:live_redirect, %{to: to}}} =
               live |> element(~s{a[href="/works/#{work}"]}) |> render_click()

      assert to == "/works/#{work}"
    end

    # Following it here is a fresh request rather than the socket message a browser sends,
    # because the harness re-establishes the connection — so what this covers is that the
    # row leads somewhere that renders, not the navigation a person makes. The session a
    # navigation actually mounts from is asserted in `PluteusWeb.EntityLiveTest`.
    test "a holding reached that way answers for its own kind", %{conn: conn} do
      work = holding("document")

      {:ok, live, _html} = live(conn, ~p"/everything?#{[category: "document"]}")

      assert {:ok, _page, html} =
               live
               |> element(~s{a[href="/works/#{work}"]})
               |> render_click()
               |> follow_redirect(Plug.Conn.put_req_header(conn, "accept", "text/html"))

      assert html =~ "a document"
    end

    test "every mode in the rail is reached the same way", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/everything")

      for {mode, at} <- Chrome.addressed(), mode != "everything" do
        assert live |> element(~s{a[href="#{at}"]}) |> has_element?(),
               "the #{mode} mode is not linked at #{at}"
      end
    end
  end

  describe "§14.1. Every surface states which principal it is acting as" do
    test "a principal with no person of its own is said to be one, in the rail too",
         %{conn: conn} do
      # The rail and the top bar are two renderings of one statement, and the rail's had
      # no words for a principal without a person: it read "Acting as" and stopped.
      {:ok, live, _html} = live(conn, ~p"/everything")

      assert live |> element("#identity-principal") |> render() =~
               "Acting as a principal with no person of its own"

      assert has_element?(
               live,
               ~s|#identity-switch[aria-label="Acting as a principal with no person of its own. Switch principal."]|
             )
    end
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

    # §12.1 puts a photograph on a grid rather than in a list, and the tile leads to the
    # viewer rather than to the entity page, since the picture is what was pressed.
    test "narrowing to a photograph renders a grid of tiles", %{conn: conn} do
      photo = named("A photograph", "photograph")

      {:ok, _live, html} = live(conn, ~p"/everything?category=photograph")

      assert html =~ ~s|href="/works/#{photo}/view"|
      refute html =~ ~s|href="/works/#{photo}"|
    end

    # §12.1 calls it a justified grid: a tile takes the width its own shape asks for, so
    # a row fills the page and everything in it stands the same height. The shape is
    # §20's figure for the category where nothing has measured the bytes (criterion 28).
    test "a tile is as wide as the shape its box reserves", %{conn: conn} do
      for _each <- 1..3, do: named("A photograph", "photograph")

      {:ok, _live, html} = live(conn, ~p"/everything?category=photograph")

      assert html =~ "flex: 1.5 0 0%"
      assert html =~ "aspect-ratio: 1.5"
    end

    # A surface headed with the mode's name while the rail says Photographs makes a
    # person read the chips to learn what they are looking at.
    test "the surface is headed by what it is showing", %{conn: conn} do
      named("A photograph", "photograph")
      named("A letter", "document")

      {:ok, _live, html} = live(conn, ~p"/everything?category=photograph,document")

      assert html =~ "Documents and Photographs"
      refute html =~ ">Everything</h1>"
    end

    test "a kind that is read keeps its rows", %{conn: conn} do
      letter = named("A letter", "document")

      {:ok, _live, html} = live(conn, ~p"/everything?category=document")

      assert html =~ ~s|href="/works/#{letter}"|
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

      assert html =~ "None of these say where they were made."
      assert html =~ "None of these say what language they are in."
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

      assert html =~ "Places"
      assert html =~ "None of these say where they were made."
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

    # The chrome names a mode and the surface parses that name against §20's own list, so
    # a name only one of them knows is a link that refuses itself when pressed.
    test "every mode the chrome names is one the registry holds" do
      named = for {slug, _n, _g, _w, _at} <- Chrome.modes(), do: slug

      assert Enum.sort(named) == Enum.sort(Surfaces.browse_modes())
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

    # §9.2 makes a mode a way of looking rather than a filter, so Sets shows what gathers
    # others and nothing else — and the count beside it has to be of that, because a
    # count taken against the whole catalogue would promise holdings Sets does not show.
    test "Sets holds what gathers others, and says so", %{conn: conn} do
      release = a_release()
      letter = named("A letter", "document")

      {:ok, _live, html} = live(conn, ~p"/sets")

      assert html =~ ~s|href="/works/#{release}"|
      refute html =~ ~s|href="/works/#{letter}"|
      assert html =~ "of 1 holding"
    end

    # §9.2 makes People the agents a household's holdings credit, and an agent is a res:
    # pressing one opens the page that is about them rather than a list narrowed by them.
    test "People lists the agents, each at its own address", %{conn: conn} do
      # A credit is written by placement and nowhere else, so this is a placed release
      # rather than rows assembled here: what the mode lists is what ingest recorded.
      MusicFixtures.library!()

      {:ok, _live, html} = live(conn, ~p"/people")

      assert html =~ "Miles Davis"
      assert html =~ ~s|href="/artists/|
    end

    test "Recently added puts what arrived last first", %{conn: conn} do
      _first = named("An early letter", "document")
      _second = named("A later letter", "document")

      {:ok, _live, html} = live(conn, ~p"/recently-added")

      assert html =~ "Recently added"
      assert html =~ "An early letter"
      assert html =~ "A later letter"
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

    # A pair names two holdings, so the manifestation each letter is held as.
    [one, other] =
      for name <- ["a letter", "the same letter"] do
        [expression] = name |> named("document") |> Catalog.expressions_of()
        [manifestation] = Catalog.manifestations_of(expression.id)
        manifestation.id
      end

    {:ok, candidate} = Dedup.propose(one, other, principal.id)

    candidate
  end

  # A nil category is what ingest leaves behind for a commentary stream: a work of its
  # own embodied in the film's manifestation, which nothing categorizes.
  # A release is a work whose expression gathers another's, which is the relation §9.2's
  # Sets mode is a way of looking at. The track it gathers is not an entry of its own,
  # which is what makes the mode's selection assertable from one pair.
  defp a_release do
    release = named("A release", "album")
    track = named("A track", "music_recording")

    [gathering | _rest] = Catalog.expressions_of(release)
    [gathered | _more] = Catalog.expressions_of(track)

    {:ok, _} = Catalog.aggregate(gathering.id, gathered.id)

    release
  end

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
