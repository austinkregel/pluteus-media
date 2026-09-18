defmodule PluteusWeb.ConformanceTest do
  @moduledoc """
  Conformance with the criteria of spec-01 §15 that are observed over HTTP.

  Each `describe` block states one numbered criterion verbatim.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Lifecycle
  alias Pluteus.Principals

  @viewer "ada@household.test"

  setup %{conn: conn} do
    {:ok, principal} = Principals.create_principal(%{role: "member"})
    {:ok, _} = Principals.bind_identity(principal.id, issuer(), @viewer)
    {:ok, %{work: work, expression: expression}} = Catalog.create_work("The Dig")

    %{
      conn: through_proxy(conn, @viewer),
      principal: principal,
      work: work,
      expression: expression
    }
  end

  defp viewer, do: through_proxy(build_conn(), @viewer)

  describe "27. A recycled entity returns 410 with no-store and a type distinct from purged" do
    test "a live entity is served", %{conn: conn, work: work} do
      conn = get(conn, "/works/#{work.id}")

      assert %{"id" => id, "kind" => "work"} = json_response(conn, 200)
      assert id == work.id
    end

    test "a recycled one is gone, and must not be cached", %{
      conn: conn,
      work: work,
      principal: principal
    } do
      {:ok, recycling} = Lifecycle.recycle(work.id, principal.id)

      conn = get(conn, "/works/#{work.id}")

      assert conn.status == 410
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      assert ["application/problem+json" <> _] = get_resp_header(conn, "content-type")

      body = Jason.decode!(conn.resp_body)
      assert String.ends_with?(body["type"], "/problems/recycled")
      assert body["status"] == 410
      assert body["restorable_until"] == DateTime.to_iso8601(recycling.purge_after)
    end

    test "a purged one is gone too, under a different problem type", %{
      conn: conn,
      work: work,
      principal: principal
    } do
      {:ok, recycling} = Lifecycle.recycle(work.id, principal.id)
      recycled = get(viewer(), "/works/#{work.id}")

      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())
      purged = get(conn, "/works/#{work.id}")

      assert purged.status == 410
      assert String.ends_with?(Jason.decode!(purged.resp_body)["type"], "/problems/purged")

      refute Jason.decode!(purged.resp_body)["type"] ==
               Jason.decode!(recycled.resp_body)["type"]
    end

    test "and its permanence may be cached", %{conn: conn, work: work, principal: principal} do
      {:ok, recycling} = Lifecycle.recycle(work.id, principal.id)
      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())

      conn = get(conn, "/works/#{work.id}")

      assert get_resp_header(conn, "cache-control") == []
    end

    test "an identifier nothing ever held is not found, not gone", %{conn: conn} do
      conn = get(conn, "/works/#{UUIDv7.generate()}")

      assert conn.status == 404
    end

    test "an expression's identifier names no work", %{conn: conn, expression: expression} do
      assert get(conn, "/works/#{expression.id}").status == 404
      assert get(viewer(), "/expressions/#{expression.id}").status == 200
    end
  end

  describe "28. A restored entity is reachable at its original identifier" do
    test "the work answers at the URI it always had", %{
      conn: conn,
      work: work,
      principal: principal
    } do
      {:ok, recycling} = Lifecycle.recycle(work.id, principal.id)
      assert get(viewer(), "/works/#{work.id}").status == 410

      {:ok, _} = Lifecycle.restore(recycling.id)

      assert %{"id" => id} = json_response(get(conn, "/works/#{work.id}"), 200)
      assert id == work.id
    end

    test "and so does everything that went into the bin with it", %{
      conn: conn,
      work: work,
      expression: expression,
      principal: principal
    } do
      {:ok, recycling} = Lifecycle.recycle(work.id, principal.id)
      assert get(viewer(), "/expressions/#{expression.id}").status == 410

      {:ok, _} = Lifecycle.restore(recycling.id)

      assert get(conn, "/expressions/#{expression.id}").status == 200
    end
  end
end
