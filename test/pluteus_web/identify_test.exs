defmodule PluteusWeb.IdentifyTest do
  @moduledoc """
  Who a rendered request is from, on a surface where refusing is not the only answer
  available.

  spec-10 Annex A.8.1 requires the vendored glyph set's notices appear in the interface
  and the design language is the household's, so those pages answer a request that
  carries no identity at all. What must not follow from that is a forged or
  misconfigured proxy header being read as an absent one, which would hand an anonymous
  render to whoever guessed the header's name.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Administration
  alias Pluteus.Principals

  describe "a request the proxy did not forward" do
    test "renders, with no principal and nothing said about contexts", %{conn: conn} do
      conn = get(conn, "/design")

      assert conn.status == 200
      assert is_nil(conn.assigns.principal)

      # No attribute at all, so `localStorage` and the stylesheet's media queries are
      # what decide — which is the household-public behaviour, not a degradation of the
      # signed-in one.
      refute html_response(conn, 200) =~ "data-stored"
    end
  end

  describe "a secret that is present and wrong is never an absent one" do
    test "a guessed secret is refused rather than rendered", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-pluteus-proxy-secret", "guessed")
        |> put_req_header("x-authentik-email", a_subject())
        |> get("/design")

      assert conn.status == 401
    end

    test "the proxy's own secret naming nobody is refused", %{conn: conn} do
      # The request came through the proxy and the proxy named no identity, which is the
      # proxy configured wrongly rather than a household-public request. Rendering it
      # would make a broken deployment look like a working one.
      conn = conn |> via_proxy() |> get("/design")

      assert conn.status == 401
    end
  end

  describe "a request the proxy forwarded" do
    test "the principal is attached", %{conn: conn} do
      conn = conn |> through_proxy(a_subject()) |> get("/design")

      assert conn.status == 200
      assert conn.assigns.principal.role == "member"
    end

    test "a retired principal is refused with the status its reason carries", %{conn: conn} do
      {:ok, principal} = Principals.create_principal(%{role: "member"})
      {:ok, admin} = Principals.create_principal(%{role: "administrator"})
      viewer = a_subject()

      {:ok, _bound} = Principals.bind_identity(principal.id, issuer(), viewer)
      {:ok, _retired} = Administration.retire_principal(admin, principal.id)

      conn = conn |> through_proxy(viewer) |> get("/design")

      assert conn.status == 403
      assert Jason.decode!(conn.resp_body)["title"] == "retired"
    end
  end
end
