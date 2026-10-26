defmodule PluteusWeb.BrowserCase do
  @moduledoc """
  A test that drives a real browser at a real surface.

  [spec-10] §17.7 names four obligations "broken by that mechanism and by nothing else,
  and invisible to automated checks" — the mechanism being the patched live document. A
  dead render is an automated check. What this is for is the handful of things that are
  only true, or only false, in a browser: where focus lands after a patch, what a live
  region says the second time, and whether a collection moves as its images arrive.

  ## One sandbox, shared with everything the browser reaches

  The sandbox is in shared mode for the test's duration, so every process the test causes
  uses the test's own connection: the request that renders the page, the live socket, and
  each LiveView it joins. What a fixture writes is visible to the page without being
  committed, and when the test ends it is rolled back together with everything the browser
  did. Nothing is left in the database for the next test that counts something to find.

  That is why a browser-driven test must run alone. Shared mode hands every process one
  connection, so two tests holding it at once would each see the other's rows — and this
  refuses an async test rather than letting that happen quietly.

  ## Nothing is bypassed to get in

  The browser reaches the interface through `Pluteus.Proxy`, which asserts an identity the
  way the deployment's own reverse proxy does and is the only thing that may. There is no
  test-only authentication path in `lib/`, and this does not add one.
  """

  use ExUnit.CaseTemplate

  alias Pluteus.Actor
  alias Pluteus.Catalog
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Ingest.Place
  alias Pluteus.IngestFixtures
  alias Pluteus.Principals
  alias Pluteus.Proxy
  alias Pluteus.Repo

  using do
    quote do
      import PluteusWeb.BrowserCase

      alias Pluteus.Browser
      alias Pluteus.Proxy
    end
  end

  setup tags do
    if tags[:async] do
      raise "a browser-driven test shares one database connection with every process the " <>
              "browser reaches, so it cannot run beside another test"
    end

    actor = Pluteus.DataCase.setup_sandbox(tags)

    principal =
      Principals.admit(
        Application.fetch_env!(:pluteus, PluteusWeb.ForwardAuth)[:issuer],
        Proxy.default_subject()
      )

    actor |> Map.new() |> Map.put(:principal, principal)
  end

  @doc """
  A browser open on a path, as the proxy's principal on a declared surface.

  Closed when the test ends, whether or not it passed: a session left open holds a
  browser, and a run of them would hold one each. It closes before the sandbox does,
  because callbacks run last-registered first, so no live view is left querying a
  connection that has gone.
  """
  @spec open!(String.t(), keyword()) :: Pluteus.Browser.t()
  def open!(path, options \\ []) do
    browser =
      Pluteus.Browser.open(
        Proxy.url(path),
        Keyword.merge([surface: "near", subject: Proxy.default_subject()], options)
      )

    on_exit(fn -> Pluteus.Browser.close(browser) end)

    browser
  end

  @doc """
  Every focusable in the shell that carries no id, described well enough to find it.

  [spec-10] §17.7's first obligation, and one stated in one place because it has to be
  asked of every state a surface can be in rather than of one page: a control that renders
  only when something is queued, or only for a kind that plays, is unidentified on exactly
  the pages a test about something else never opens.
  """
  @spec unidentified(Pluteus.Browser.t()) :: [String.t()]
  def unidentified(browser) do
    Pluteus.Browser.evaluate(browser, """
    const focusable = "a[href], button, input:not([type=hidden]), select, textarea, " +
      "[tabindex]:not([tabindex='-1'])";
    return [...document.querySelector("#shell").querySelectorAll(focusable)]
      .filter((e) => !e.id)
      .map((e) => [
        e.tagName.toLowerCase(),
        (e.getAttribute("aria-label") || e.textContent || "").trim().slice(0, 40),
        "in #" + ((e.closest("[id]") || {}).id || "nothing")
      ].join(" "));
    """)
  end

  @doc """
  A two-track release ingested from a real recording, answered as its work: what a test
  needs something actually playing for.
  """
  @spec a_release!() :: Ecto.UUID.t()
  def a_release! do
    inbox = IngestFixtures.inbox!()
    prefix = IngestFixtures.unique_prefix()

    for {path, bytes} <- %{
          "#{prefix}/album.flac" => IngestFixtures.media!(:flac, duration: 6),
          "#{prefix}/album.cue" => """
          TITLE "Kind of Blue"
          PERFORMER "Miles Davis"
          FILE "album.flac" WAVE
            TRACK 01 AUDIO
              TITLE "So What"
              INDEX 01 00:00:00
            TRACK 02 AUDIO
              TITLE "Freddie Freeloader"
              INDEX 01 00:03:00
          """
        },
        do: IngestFixtures.drop!(inbox, path, bytes)

    ids = inbox |> IngestFixtures.acquire_settled!() |> IngestFixtures.acquired()
    IngestFixtures.place_all!(inbox)
    Normalize.normalize_due()

    album = ids |> Enum.map(&Ingest.get_acquisition!/1) |> Enum.find(&(&1.media_class == :audio))
    release = Repo.get!(DigitalItem, album.digital_item_id).manifestation_id

    [expression | _rest] = Catalog.expressions_in(release)
    expression.work_id
  end

  @doc """
  A browser with a release pressed play on from its row, the way a person starts one, and
  left until the medium has actually begun.
  """
  @spec playing!(Ecto.UUID.t()) :: Pluteus.Browser.t()
  def playing!(release) do
    browser = open!("/everything?category=album")

    Pluteus.Browser.click(browser, "#play-#{release}")

    Pluteus.Browser.await(browser, """
    const m = document.querySelector("#transport-medium");
    return !!m && !m.paused && m.currentTime > 0.3;
    """)

    browser
  end

  @doc """
  A holding the catalogue holds, named and of a kind, written as the acting principal.
  """
  @spec holding!(Ecto.UUID.t(), String.t(), String.t()) :: Ecto.UUID.t()
  def holding!(principal_id, name, category) do
    Actor.as(principal_id, fn ->
      {:ok, %{work: work}} = Catalog.create_work(%{nomen_string: name, provenance: :automatic})
      {:ok, _} = Catalog.categorize(work.id, Place.category_scheme(), category, :automatic)
      work.id
    end)
  end
end
