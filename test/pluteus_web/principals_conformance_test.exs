defmodule PluteusWeb.PrincipalsConformanceTest do
  @moduledoc """
  Conformance with spec-06 §7 for the criteria observed through the
  authenticating proxy: identity, onboarding and guest reads.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Administration
  alias Pluteus.Catalog
  alias Pluteus.Onboarding
  alias Pluteus.Principals

  describe "3. sub alone is never accepted: the proxy's identity is paired with its issuer" do
    test "a principal mapped under another issuer is not reached", %{conn: conn} do
      {:ok, principal} = Principals.create_principal(%{role: "member"})

      {:ok, _} =
        Principals.bind_identity(principal.id, "https://elsewhere.test", "ada@household.test")

      {:ok, %{work: work}} = Catalog.create_work("The Dig")

      conn = get(through_proxy(conn, "ada@household.test"), "/works/#{work.id}")

      assert conn.status == 403
      assert Jason.decode!(conn.resp_body)["title"] == "unknown-identity"
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

  describe "9. A guest reads what it was granted and nothing else" do
    test "the granted work is served and another is not there", %{conn: conn} do
      {:ok, admin} = Principals.create_principal(%{role: "administrator"})
      {:ok, guest} = Administration.create_principal(admin, %{role: "guest"})
      {:ok, _} = Principals.bind_identity(guest.id, issuer(), "cousin@elsewhere.test")
      {:ok, %{work: granted}} = Catalog.create_work("The Dig")
      {:ok, %{work: other}} = Catalog.create_work("Middlemarch")
      {:ok, _} = Administration.grant_guest(admin, guest.id, granted.id)

      assert get(through_proxy(conn, "cousin@elsewhere.test"), "/works/#{granted.id}").status ==
               200

      assert get(through_proxy(build_conn(), "cousin@elsewhere.test"), "/works/#{other.id}").status ==
               404
    end
  end

  describe "12. Onboarding needs evidence of host access and closes once anyone exists" do
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

    test "any other secret is refused", %{conn: conn} do
      {:ok, _secret} = Onboarding.prepare()

      conn =
        conn
        |> through_proxy("owner@household.test")
        |> post("/onboarding", %{"secret" => "not the one on the console"})

      assert conn.status == 403
      refute Onboarding.onboarded?()
    end

    test "once a principal exists it is not there at all", %{conn: conn} do
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

    test "no identity names it, so no request can act as it", %{conn: conn} do
      {:ok, secret} = Onboarding.prepare()
      {:ok, %{system: system}} = Onboarding.claim(secret, {issuer(), "owner@household.test"})

      assert Principals.identities_of(system.id) == []

      conn = get(through_proxy(conn, "system"), "/works/#{Ecto.UUID.generate()}")
      assert conn.status == 403
    end
  end
end
