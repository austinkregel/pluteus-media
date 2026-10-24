defmodule PluteusWeb.Browser.AnnouncementTest do
  @moduledoc """
  Criterion 42: a live region exists before it speaks, and an unchanged message does not
  re-announce.

  [spec-10] §17.7 gives the second half as a rule about computation — "Announcement
  content MUST be computed so that re-rendering an unchanged message produces no change."
  A screen reader announces a polite region when its contents change, and replacing a text
  node with an identical one is a change to the document even though it is not a change to
  the words. So the obligation is about the DOM and not about the string, and the only
  instrument that sees it is one watching the document.

  That is what a `MutationObserver` is. Asserting the text instead would pass while the
  region was being torn out and rebuilt on every patch, which is the fault being guarded
  against.

  Both halves are asserted together, because either alone is passed by a region that never
  changes at all: the first clearing must reach the region, and the second must not.
  """

  use PluteusWeb.BrowserCase

  alias Pluteus.Ingest

  @kind "text_is_not_utf8"

  setup do
    %{findings: for(_each <- 1..2, do: recorded!())}
  end

  describe "42. A live region is rendered before it speaks" do
    test "it is present and empty before anything has been said" do
      browser = open!("/findings")

      assert Browser.showing?(browser, "#shell-announcement")

      assert Browser.evaluate(browser, """
             return document.querySelector("#shell-announcement").textContent.trim();
             """) == ""
    end
  end

  describe "42. An unchanged message produces no re-announcement" do
    test "the first message reaches the region and the second does not touch it",
         %{findings: [one, two]} do
      browser = open!("/findings")

      # A group is collapsed until someone opens it, and a closed `details` is laid out but
      # not hit-testable, so the control inside it is reached the way a person reaches it.
      Browser.click(browser, "#group-text_is_not_utf8-summary")
      Browser.await(browser, ~s|return document.querySelector("#group-text_is_not_utf8").open|)

      watch(browser)

      Browser.click(browser, "#clear-#{one.id}")
      Browser.await(browser, ~s|return window.__mutations.length > 0|)

      assert said(browser) == "Cleared."

      # Clearing one re-renders its group, which closes again, so it is opened as before.
      # Nothing here touches the region being watched.
      Browser.click(browser, "#group-text_is_not_utf8-summary")
      Browser.await(browser, ~s|return document.querySelector("#clear-#{two.id}")|)

      # The same words again. §17.7 asks that this reach the document as nothing at all,
      # because a polite region announces what changed in it and an identical text node
      # put back is still a change.
      forget(browser)

      Browser.click(browser, "#clear-#{two.id}")
      Browser.await(browser, ~s|return !document.querySelector("#clear-#{two.id}")|)

      assert said(browser) == "Cleared."

      assert mutations(browser) == [],
             "the region was touched although what it says did not change: " <>
               inspect(mutations(browser))
    end
  end

  defp watch(browser) do
    Browser.evaluate(browser, """
    window.__mutations = [];
    const region = document.querySelector("#shell-announcement");
    window.__observer = new MutationObserver((records) => {
      records.forEach((r) => window.__mutations.push(r.type));
    });
    window.__observer.observe(region, {childList: true, characterData: true, subtree: true,
                                       attributes: true});
    return true;
    """)
  end

  defp forget(browser) do
    Browser.evaluate(browser, "window.__mutations = []; return true;")
  end

  defp mutations(browser), do: Browser.evaluate(browser, "return window.__mutations")

  defp said(browser) do
    Browser.evaluate(browser, """
    return document.querySelector("#shell-announcement").textContent.trim();
    """)
  end

  defp recorded! do
    Ingest.record_finding(%{
      stage: :normalize,
      kind: @kind,
      permanent: false,
      detail: %{},
      location: "a6/89/#{Ecto.UUID.generate()}",
      recorded_at: DateTime.utc_now()
    })
  end
end
