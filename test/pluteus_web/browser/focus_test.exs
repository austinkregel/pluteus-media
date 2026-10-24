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
