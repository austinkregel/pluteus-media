defmodule PluteusWeb.Browser.SearchTest do
  @moduledoc """
  Criterion 52 in a browser: reaching search from a mode keeps the facet set, and keeps
  what is playing.

  The second half is what a dead render cannot show. Search is a surface of its own, so
  reaching it replaces the page's view, and whether the transport survives that is a
  property of how the field's submission is answered — a navigation keeps the player, a
  page load stops it — which only a page that is actually playing can be watched for.
  """

  use PluteusWeb.BrowserCase

  describe "52. Reaching search from a mode does not discard the active facet set" do
    test "a search typed on a narrowed surface keeps the facets and the playing medium" do
      release = a_release!()
      browser = playing!(release)

      # Marked, so the medium afterwards can be told from a new one that merely started.
      Browser.evaluate(browser, """
      const m = document.querySelector("#transport-medium");
      m.__marked = true;
      window.__from = m.currentTime;
      return true;
      """)

      Browser.type(browser, "#rail-search", "kind")
      Browser.await(browser, "return window.location.pathname === '/search'")
      Browser.await(browser, "return window.liveSocket.main.isConnected()")

      assert Browser.evaluate(browser, "return window.location.search") =~ "category=album"
      assert Browser.showing?(browser, "#row-#{release}")

      assert Browser.evaluate(browser, """
             const m = document.querySelector("#transport-medium");
             return m.__marked === true && !m.paused && m.currentTime >= window.__from;
             """),
             "the medium playing before the search was not the one playing after it"
    end
  end
end
