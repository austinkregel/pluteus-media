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

  describe "41. Every focusable carries the identity the restoration turns on" do
    test "no focusable in the shell is without an id", %{principal: principal} do
      holding!(principal.id, "a photograph", "photograph")

      browser = open!("/everything?category=photograph")

      unidentified =
        Browser.evaluate(browser, """
        const focusable = "a[href], button, input, select, textarea, [tabindex]:not([tabindex='-1'])";
        return [...document.querySelector("#shell").querySelectorAll(focusable)]
          .filter((e) => !e.id)
          .map((e) => [
            e.tagName.toLowerCase(),
            (e.getAttribute("aria-label") || e.textContent || "").trim().slice(0, 40),
            "in #" + ((e.closest("[id]") || {}).id || "nothing")
          ].join(" "));
        """)

      assert unidentified == [],
             "#{length(unidentified)} focusable element(s) carry no id:\n" <>
               Enum.map_join(unidentified, "\n", &"  #{&1}")
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
end
