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
  alias Pluteus.Ingest.Place
  alias Pluteus.Principals
  alias Pluteus.Proxy

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
