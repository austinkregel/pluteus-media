defmodule PluteusWeb.PrincipalsConformanceTest do
  @moduledoc """
  Conformance with spec-06 §7 for the criteria observed through the
  authenticating proxy: identity, admission and onboarding.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Administration
  alias Pluteus.Catalog
  alias Pluteus.Onboarding
  alias Pluteus.Principals

  describe "3. sub alone is never accepted: the proxy's identity is paired with its issuer" do
    test "a principal mapped under another issuer is not the one served", %{conn: conn} do
      {:ok, elsewhere} = Principals.create_principal(%{role: "member"})

      {:ok, _} =
        Principals.bind_identity(elsewhere.id, "https://elsewhere.test", "ada@household.test")

      {:ok, %{work: work}} = Catalog.create_work("The Dig")

      assert get(through_proxy(conn, "ada@household.test"), "/works/#{work.id}").status == 200

      served = Principals.principal_for(issuer(), "ada@household.test")
      refute served.id == elsewhere.id
    end
  end

  describe "the proxy is the only way identity arrives" do
    setup do
      {:ok, principal} = Principals.create_principal(%{role: "member"})
      {:ok, _} = Principals.bind_identity(principal.id, issuer(), "ada@household.test")
      {:ok, %{work: work}} = Catalog.create_work("The Dig")
      %{principal: principal, work: work}
    end

    test "identity headers without the proxy's secret are not read", %{conn: conn, work: work} do
      conn =
        conn
        |> put_req_header("x-authentik-email", "ada@household.test")
        |> get("/works/#{work.id}")

      assert conn.status == 401
    end

    test "a wrong secret is the same as none", %{conn: conn, work: work} do
      conn =
        conn
        |> put_req_header("x-pluteus-proxy-secret", "guessed")
        |> put_req_header("x-authentik-email", "ada@household.test")
        |> get("/works/#{work.id}")

      assert conn.status == 401
    end

    test "through the proxy the member is served", %{conn: conn, work: work} do
      assert get(through_proxy(conn, "ada@household.test"), "/works/#{work.id}").status == 200
    end

    test "a retired principal is refused", %{conn: conn, work: work, principal: principal} do
      {:ok, admin} = Principals.create_principal(%{role: "administrator"})
      {:ok, _} = Administration.retire_principal(admin, principal.id)

      conn = get(through_proxy(conn, "ada@household.test"), "/works/#{work.id}")

      assert conn.status == 403
      assert Jason.decode!(conn.resp_body)["title"] == "retired"
    end
  end

  describe "9. Whoever the provider admits is served as a Member on their first request" do
    test "a cousin added to the household's team is let in without further admission", %{
      conn: conn
    } do
      {:ok, %{work: work}} = Catalog.create_work("The Dig")

      assert get(through_proxy(conn, "cousin@elsewhere.test"), "/works/#{work.id}").status == 200
      assert Principals.principal_for(issuer(), "cousin@elsewhere.test").role == "member"
    end
  end

  describe "12. Onboarding needs evidence of host access and closes once an Administrator exists" do
    @describetag :no_actor

    test "the console's secret makes the claimant the first Administrator", %{conn: conn} do
      {:ok, secret} = Onboarding.prepare()

      conn =
        conn
        |> through_proxy("owner@household.test")
        |> post("/onboarding", %{"secret" => secret})

      assert %{"administrator" => id} = json_response(conn, 201)
      assert Principals.principal_for(issuer(), "owner@household.test").id == id
      assert Principals.get_principal(id).role == "administrator"
      assert %{role: "system"} = Principals.system!()
    end

    test "someone who arrived first as a member is promoted, not duplicated", %{conn: conn} do
      member = Principals.admit(issuer(), "owner@household.test")
      {:ok, secret} = Onboarding.prepare()

      conn =
        conn
        |> through_proxy("owner@household.test")
        |> post("/onboarding", %{"secret" => secret})

      assert %{"administrator" => id} = json_response(conn, 201)
      assert id == member.id
    end

    test "any other secret is refused", %{conn: conn} do
      {:ok, _secret} = Onboarding.prepare()

      conn =
        conn
        |> through_proxy("owner@household.test")
        |> post("/onboarding", %{"secret" => "not the one on the console"})

      assert conn.status == 403
      refute Onboarding.onboarded?()
    end

    test "once an Administrator exists it is not there at all", %{conn: conn} do
      {:ok, secret} = Onboarding.prepare()
      {:ok, _} = Onboarding.claim(secret, {issuer(), "owner@household.test"})

      conn =
        conn
        |> through_proxy("someone@household.test")
        |> post("/onboarding", %{"secret" => secret})

      assert conn.status == 404
      assert Onboarding.prepare() == {:error, :already_onboarded}
    end
  end

  describe "13. The System principal cannot be reached through the proxy" do
    @describetag :no_actor

    test "no identity names it, so a request claiming to be it is someone else", %{conn: conn} do
      {:ok, secret} = Onboarding.prepare()
      {:ok, %{system: system}} = Onboarding.claim(secret, {issuer(), "owner@household.test"})

      assert Principals.identities_of(system.id) == []

      get(through_proxy(conn, "system"), "/works/#{Ecto.UUID.generate()}")

      arrived = Principals.principal_for(issuer(), "system")
      refute arrived.id == system.id
      assert arrived.role == "member"
    end
  end
end
