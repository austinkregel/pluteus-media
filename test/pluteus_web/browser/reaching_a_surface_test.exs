defmodule PluteusWeb.Browser.ReachingASurfaceTest do
  @moduledoc """
  That a browser can reach a surface at all, which everything else driven by one rests on.

  Asserted before the obligations it is there to assert, because each of those is a claim
  about a patched live document and none of them means anything if the page never arrived
  or the socket never upgraded.
  """

  use PluteusWeb.BrowserCase

  describe "§4.4, §9.2. A browser reaches a declared surface as the proxy's principal" do
    test "a narrowed surface renders the holding it narrowed to", %{principal: principal} do
      # Narrowed, because the gateway unnarrowed is bands of kinds and counts: a holding's
      # own name is on a row, and rows are what a narrowing leaves.
      holding!(principal.id, "a photograph", "photograph")

      browser = open!("/everything?category=photograph")

      assert Browser.showing?(browser, "#shell")
      assert Browser.document(browser) =~ "a photograph"
    end

    test "the live socket is a websocket, not the long poll it falls back to" do
      # A page on the fallback patches nothing, so every obligation §17.7 names about a
      # patched document would otherwise be asserted against a document never patched —
      # and the fallback is remembered per tab, so one slow connection hides the lot.
      browser = open!("/everything")

      assert Browser.transport(browser) == "WebSocket"
    end

    test "a surface not declared is asked for rather than guessed" do
      # §4.4 forbids inferring a surface, so a browser that has not declared one is asked
      # before anything renders. The principal is asserted either way, which is what makes
      # this about the declaration rather than about identity.
      browser = open!("/everything", surface: nil)

      assert Browser.evaluate(browser, "return window.location.pathname") == "/surface"
    end
  end
end
