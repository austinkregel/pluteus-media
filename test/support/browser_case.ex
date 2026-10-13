defmodule PluteusWeb.BrowserCase do
  @moduledoc """
  A test that drives a real browser at a real surface.

  [spec-10] §17.7 names four obligations "broken by that mechanism and by nothing else,
  and invisible to automated checks" — the mechanism being the patched live document. A
  dead render is an automated check. What this is for is the handful of things that are
  only true, or only false, in a browser: where focus lands after a patch, what a live
  region says the second time, and whether a collection moves as its images arrive.

  ## It commits, and it runs alone

  A browser's request is a separate process with its own connection, so it cannot join
  this test's sandbox transaction and cannot see anything held uncommitted in one. These
  tests therefore commit for real and remove what they wrote, which is the shape
  `Pluteus.ChangeFeedTest` already uses and for the same reason.

  What was written is found rather than remembered: every res this test's principal
  created is recorded in `catalog_writes`, so the cleanup reads that and goes back down
  the tree. A fixture that grew a row nobody listed is then still removed.

  ## Nothing is bypassed to get in

  The browser reaches the interface through `Pluteus.Proxy`, which asserts an identity the
  way the deployment's own reverse proxy does and is the only thing that may. There is no
  test-only authentication path in `lib/`, and this does not add one.
  """

  use ExUnit.CaseTemplate

  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.SQL.Sandbox
  alias Pluteus.Actor
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Category
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Extent
  alias Pluteus.Catalog.Manifestation
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Res
  alias Pluteus.Catalog.Work
  alias Pluteus.Ingest.Place
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

  setup do
    :ok = Sandbox.mode(Repo, :auto)
    :ok = Sandbox.mode(Pluteus.Jobs.Repo, :auto)

    principal =
      Principals.admit(
        Application.fetch_env!(:pluteus, PluteusWeb.ForwardAuth)[:issuer],
        Proxy.default_subject()
      )

    on_exit(fn ->
      remove!(principal.id)
      Sandbox.mode(Repo, :manual)
      Sandbox.mode(Pluteus.Jobs.Repo, :manual)
    end)

    %{principal: principal}
  end

  @doc """
  A browser open on a path, as the proxy's principal on a declared surface.

  Closed when the test ends, whether or not it passed: a session left open holds a
  browser, and a run of them would hold one each.
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

  # Everything this principal wrote, including what it did not ask for. Rendering a
  # surface enrols a device (spec-06 §4.1) and may leave a queue and a position behind, so
  # a cleanup that took only the fixtures would leave a device per page load — committed,
  # and visible to every test that counts them.
  #
  # Then every res its writes created, taken down in the order the keys allow. A work is
  # five rows, two links and a category, each keyed on a res about to go, so each goes
  # before its res does.
  defp remove!(principal_id) do
    id = Ecto.UUID.dump!(principal_id)

    res_ids =
      Repo.all(
        from w in "catalog_writes",
          where: w.principal_id == ^id and w.table_name == "res" and w.operation == "INSERT",
          select: type(fragment("(?->>'id')::uuid", w.row_key), Ecto.UUID)
      )

    for table <- ~w(resume_positions stars ratings playlists play_queues now_playing) do
      Repo.query!("DELETE FROM #{table} WHERE principal_id = $1", [id])
    end

    Repo.query!("DELETE FROM events WHERE principal_id = $1", [id])

    # The credential goes before the device: a device is shared and outlives any one
    # principal's enrolment on it, so it is removed only once nothing references it.
    Repo.query!("DELETE FROM device_credentials WHERE principal_id = $1", [id])

    Repo.query!("""
    DELETE FROM devices WHERE NOT EXISTS
      (SELECT 1 FROM device_credentials c WHERE c.device_id = devices.id)
    """)

    {:ok, _} =
      Actor.as(principal_id, fn ->
        Repo.delete_all(from e in Extent, where: e.res_id in ^res_ids)
        Repo.delete_all(from c in Category, where: c.res_id in ^res_ids)

        Repo.delete_all(
          from e in Embodiment,
            where: e.expression_id in ^res_ids or e.manifestation_id in ^res_ids
        )

        Repo.delete_all(from m in Manifestation, where: m.id in ^res_ids)
        Repo.delete_all(from e in Expression, where: e.id in ^res_ids)
        Repo.delete_all(from w in Work, where: w.id in ^res_ids)
        Repo.delete_all(from n in Nomen, where: n.id in ^res_ids or n.res_id in ^res_ids)
        {:ok, Repo.delete_all(from r in Res, where: r.id in ^res_ids)}
      end)

    Repo.query!("DELETE FROM catalog_writes WHERE principal_id = $1", [id])
    Repo.query!("DELETE FROM principal_identities WHERE principal_id = $1", [id])
    Repo.query!("DELETE FROM principals WHERE id = $1", [id])
  end
end
