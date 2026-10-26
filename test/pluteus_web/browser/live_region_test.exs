defmodule PluteusWeb.Browser.LiveRegionTest do
  @moduledoc """
  Criterion 43: no live region contains a position, a buffer state or a progress value.

  [spec-10] §17.7 gives the reason in its heading — "A live region is not a telemetry
  channel" — and the detail beneath it: playback position, buffer state and scan progress
  are rendered outside any live region, and the position slider is never inside one,
  because its value is announced when a person moves it and a live region makes it
  announce continuously.

  The criterion is about every live region and every value, so the structural check takes
  all of each: every element whose politeness is not off, against every element carrying
  a value a person scrubs or watches. And the failure the section exists for is something
  that *ticks* — a value that changes as playback runs — which a list of selectors can
  miss and a document watched while something plays cannot. So the second check plays a
  real recording, records every node that changes, and asks whether any of them is inside
  a region.

  Both are measured against a release actually playing, because that is the state in
  which the values exist and change.
  """

  use PluteusWeb.BrowserCase

  # What makes an element a live region: an explicit politeness other than off, or one of
  # the roles whose implicit politeness is not off. `timer` is left out because its implicit
  # politeness is off, which is the whole reason the role exists.
  @live """
  const live = (node) => {
    for (let e = node && node.nodeType === 1 ? node : node && node.parentElement;
         e && e !== document.documentElement;
         e = e.parentElement) {
      const politeness = e.getAttribute("aria-live");
      if (politeness && politeness !== "off") return e;
      if (["status", "alert", "log", "marquee"].includes(e.getAttribute("role"))) return e;
    }
    return null;
  };
  const named = (e) => e ? (e.id ? "#" + e.id : e.tagName.toLowerCase()) : null;
  """

  setup do
    %{release: a_release!()}
  end

  describe "43. No live region contains a position, a buffer state or a progress value" do
    test "no value a person scrubs or watches sits inside any live region",
         %{release: release} do
      browser = playing!(release)

      %{"regions" => regions, "carriers" => carriers, "inside" => inside} =
        Browser.evaluate(browser, """
        #{@live}
        const regions = [...document.querySelectorAll("*")].filter((e) => live(e) === e);
        const carriers = [...document.querySelectorAll(
          "input[type=range], progress, meter, [aria-valuenow], [aria-valuetext], " +
          "[role=slider], [role=progressbar], [role=meter], [role=timer], #transport-elapsed"
        )];
        return {
          regions: regions.map(named),
          carriers: carriers.map(named),
          inside: carriers.filter((c) => live(c)).map((c) => named(c) + " in " + named(live(c)))
        };
        """)

      # Without both of these the last assertion is true of an empty page.
      assert regions != [], "no live region was rendered, so this asserts nothing"
      assert carriers != [], "no value carrier was rendered, so this asserts nothing"

      assert inside == [],
             "a value is rendered inside a live region, which would announce it as it " <>
               "changed: #{inspect(inside)}"
    end

    test "nothing that changes while it plays changes inside a live region",
         %{release: release} do
      browser = playing!(release)

      # Watched only once it is playing, so what is recorded is what changes as playback
      # runs rather than what changed once when it started. A region saying "now playing"
      # when a person presses play is a message; a region changing every second is the
      # telemetry the section forbids.
      Browser.evaluate(browser, """
      #{@live}
      window.__changed = [];
      new MutationObserver((records) => records.forEach((r) => {
        window.__changed.push({at: named(r.target.nodeType === 1 ? r.target : r.target.parentElement),
                               region: named(live(r.target))});
      })).observe(document.body, {subtree: true, childList: true, characterData: true,
                                  attributes: true});
      window.__from = document.querySelector("#transport-medium").currentTime;
      return true;
      """)

      Process.sleep(2_500)

      %{"changed" => changed, "advanced" => advanced} =
        Browser.evaluate(browser, """
        return {changed: window.__changed,
                advanced: document.querySelector("#transport-medium").currentTime - window.__from};
        """)

      # Otherwise a page where nothing played would pass.
      assert advanced > 1.0, "playback advanced #{advanced}s, so nothing was watched ticking"
      assert changed != [], "nothing on the page changed while it played"

      in_regions = changed |> Enum.filter(& &1["region"]) |> Enum.uniq()

      assert in_regions == [],
             "these changed inside a live region while it played: #{inspect(in_regions)}"
    end

    test "nothing focusable on a playing transport is without an id", %{release: release} do
      # The controls a loaded transport draws are not drawn when nothing is queued, so the
      # chrome's identity check on an idle page cannot see them; and the queue's entries
      # are drawn only once it is opened.
      browser = playing!(release)

      Browser.click(browser, "#transport-queue-toggle")
      Browser.await(browser, ~s|return !!document.querySelector("#transport-queue li button")|)

      found = unidentified(browser)

      assert found == [],
             "#{length(found)} focusable element(s) carry no id:\n" <>
               Enum.map_join(found, "\n", &"  #{&1}")
    end
  end
end
