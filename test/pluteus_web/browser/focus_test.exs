defmodule PluteusWeb.Browser.FocusTest do
  @moduledoc """
  Criterion 41's first obligation: every focusable carries the identity restoration needs.

  [spec-10] §17.7 states it and names where the rest is kept — "hold this in the client
  hook that records the identity, which is the assertion point." The hook is `Focus` in
  `assets/js/app.js`, mounted on the shell so its walk can cross between the chrome and
  the surface.

  The hook records `event.target.id` and `restore()` opens with `if (!this.remembered)
  return`, so a focusable without an id is remembered as nothing and restored to nothing.
  Everything else §17.7 asks for rests on this, which is why it is asserted on its own and
  against a rendered document rather than against markup: what counts is what the browser
  finds focusable, not what a template appears to emit.
  """

  use PluteusWeb.BrowserCase

  import Pluteus.IngestFixtures

  alias Pluteus.Catalog
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Presentation.Generate
  alias Pluteus.Reading
  alias Pluteus.Storage

  describe "41. Every surface's focusables carry the identity the restoration turns on" do
    # One per surface, because each draws controls the others do not: a player's track
    # choices, a reader's page controls, a finding's clear button. A check asked of the
    # gateway alone passed while the player's track buttons went unnamed.
    test "the player" do
      film = placed!("home video/#{unique_prefix()}/duck.mkv", media!(:film))

      assert_identified(open!("/works/#{film}/play"))
    end

    test "the viewer" do
      photograph = placed!("photos/#{unique_prefix()}/IMG_0001.png", media!(:png))

      assert_identified(open!("/works/#{photograph}/view"))
    end

    test "the reader" do
      pages = for n <- 1..3, do: {"page-#{n}.png", comic_page(n)}
      comic = placed!("#{unique_prefix()}/Excitebike Weekly 001.cbz", cbz(pages))

      assert_identified(open!("/works/#{comic}/read"))
    end

    test "the reader of a document" do
      letters = placed!("#{unique_prefix()}/letters.txt", "Dear Ada\n\fand Thomas\n")
      generated!(letters, Reading.profile())

      assert_identified(open!("/works/#{letters}/read"))
    end

    test "an entity page" do
      film = placed!("home video/#{unique_prefix()}/duck.mkv", media!(:film))

      assert_identified(open!("/works/#{film}"))
    end

    test "the findings surface" do
      Ingest.record_finding(%{
        stage: :normalize,
        kind: "text_is_not_utf8",
        permanent: false,
        detail: %{},
        location: "a6/89/#{Ecto.UUID.generate()}",
        recorded_at: DateTime.utc_now()
      })

      assert_identified(open!("/findings"))
    end
  end

  describe "41. Every focusable carries the identity the restoration turns on" do
    test "no focusable in the shell is without an id", %{principal: principal} do
      # A kind that plays beside one that does not, because a row of a playing kind
      # carries a control the other does not — and a page holding only documents would
      # pass while every album row's play button went unnamed.
      holding!(principal.id, "a letter", "document")
      holding!(principal.id, "a record", "album")

      browser = open!("/everything?category=album,document")

      found = unidentified(browser)

      assert found == [],
             "#{length(found)} focusable element(s) carry no id:\n" <>
               Enum.map_join(found, "\n", &"  #{&1}")
    end

    test "an element that survives a patch keeps focus", %{principal: principal} do
      # Focus in the chrome, the patch in the surface: §17.7's walk has to cross between
      # them, which is why the hook is mounted on the shell that holds both.
      #
      # The click is dispatched rather than performed, because a real one would move focus
      # to the chip and the question is what happens to focus that is somewhere else.
      holding!(principal.id, "a letter", "document")

      browser = open!("/everything?category=document")

      Browser.focus(browser, "#mode-everything")
      assert {_tag, "mode-everything"} = Browser.focused(browser)

      Browser.evaluate(browser, """
      document.querySelector("#narrowed-category-document").click();
      return true;
      """)

      Browser.await(browser, "return window.location.search === ''")

      assert {_tag, "mode-everything"} = Browser.focused(browser)
    end

    test "where the focused element is gone, focus moves on rather than being lost",
         %{principal: principal} do
      # The case §17.7 exists for. Removing the chip a person is on destroys the focused
      # element, and LiveView restores nothing of its own: a focused link is neither
      # protected from a patch nor put back after one, so focus falls to the document and
      # a keyboard is at the top of the page again with no notice that anything moved.
      holding!(principal.id, "a letter", "document")

      browser = open!("/everything?category=document")

      Browser.focus(browser, "#narrowed-category-document")
      assert {_tag, "narrowed-category-document"} = Browser.focused(browser)

      Browser.click(browser, "#narrowed-category-document")
      Browser.await(browser, "return window.location.search === ''")

      {tag, id} = Browser.focused(browser)

      refute tag == "body",
             "focus fell to the document after the focused element was removed"

      refute id == "",
             "focus landed on something carrying no identity, so the next patch loses it"
    end

    test "a route change keeps focus on an element the new surface also carries" do
      # A mode is a route, so moving between two replaces the whole view and with it the
      # element the hook is mounted on. The rail is drawn again on the far side with the
      # same identities, so the control the person pressed is there to return to.
      browser = open!("/everything")

      Browser.focus(browser, "#mode-recently_added")
      Browser.press(browser, "#mode-recently_added")
      Browser.await(browser, "return window.location.pathname === '/recently-added'")
      Browser.await(browser, "return window.liveSocket.main.isConnected()")

      assert {_tag, "mode-recently_added"} = Browser.focused(browser)
    end

    test "a route change away from the pressed element moves focus on rather than losing it",
         %{principal: principal} do
      # The row a person pressed belongs to the surface they left, so the page they arrive
      # on cannot hold it, and focus has to land on something there rather than the body.
      work = holding!(principal.id, "a letter", "document")

      browser = open!("/everything?category=document")

      Browser.press(browser, "#row-#{work}")
      Browser.await(browser, "return window.location.pathname === '/works/#{work}'")
      Browser.await(browser, "return window.liveSocket.main.isConnected()")

      {tag, id} = Browser.focused(browser)

      refute tag == "body", "focus fell to the document after the route change"
      refute id == "", "focus landed on something carrying no identity"
    end

    test "a reconnection keeps focus where it was" do
      browser = open!("/everything")

      Browser.focus(browser, "#mode-everything")

      # The socket dropped and joined again, as it is when a server restarts or a network
      # blinks. The view rejoins and is rendered afresh.
      Browser.evaluate(browser, "window.liveSocket.disconnect(); return true;")
      Browser.await(browser, "return !window.liveSocket.main.isConnected()")
      Browser.evaluate(browser, "window.liveSocket.connect(); return true;")
      Browser.await(browser, "return window.liveSocket.main.isConnected()")

      assert {_tag, "mode-everything"} = Browser.focused(browser)
    end

    test "the identity is the thing addressed, not where it sits", %{principal: principal} do
      # Content-derived rather than positional, which is the half of §17.7's wording that
      # decides whether restoration lands on the right element or merely on an element: an
      # id counted off the page would, after a removal, name whatever moved up into it.
      # A document rather than a photograph, because §12.1 draws photographs as a
      # justified grid and the row is what carries an identity derived from the holding.
      work = holding!(principal.id, "a letter", "document")

      browser = open!("/everything?category=document")

      assert Browser.showing?(browser, "#row-#{work}")
      assert Browser.showing?(browser, "#narrowed-category-document")
      assert Browser.showing?(browser, "#mode-everything")
    end
  end

  defp assert_identified(browser) do
    found = unidentified(browser)

    assert found == [],
           "#{length(found)} focusable element(s) carry no id:\n" <>
             Enum.map_join(found, "\n", &"  #{&1}")
  end

  defp generated!(work, profile) do
    [expression | _rest] = Catalog.expressions_of(work)
    [manifestation | _more] = Catalog.manifestations_of(expression.id)

    {:ok, made} = Generate.run(manifestation.id, profile)
    on_exit(fn -> Storage.delete(made.location) end)
  end

  # A holding placed and normalized from the inbox, answered as its work.
  defp placed!(path, bytes) do
    inbox = inbox!()
    drop!(inbox, path, bytes)

    [id] = inbox |> acquire_settled!() |> acquired()
    place_all!(inbox)
    Normalize.normalize_due()

    id |> Ingest.get_acquisition!() |> Map.fetch!(:digital_item_id) |> Catalog.work_of()
  end
end
