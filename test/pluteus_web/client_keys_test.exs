defmodule PluteusWeb.ClientKeysTest do
  @moduledoc """
  Client keys and the OpenSubsonic envelope: spec-07 §3, §6.1, §6.2 and
  criteria 1 to 5 and 14 to 16.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Administration
  alias Pluteus.Principals
  alias Pluteus.Principals.DeviceCredential
  alias Pluteus.Repo

  setup %{conn: conn} do
    minted =
      conn
      |> through_proxy("ada@example.test")
      |> post("/devices", %{"label" => "Symfonium on phone"})
      |> json_response(201)

    %{key: minted["key"], device_id: minted["device"]["id"]}
  end

  describe "2. A client key is shown once and stored only as a digest" do
    test "the key is returned at minting and never listed", %{conn: conn, key: key, device_id: id} do
      principal = Principals.principal_for(issuer(), "ada@example.test")
      credential = Repo.get_by!(DeviceCredential, device_id: id, principal_id: principal.id)

      assert String.starts_with?(key, "pk_")
      assert credential.key_digest == :sha256 |> :crypto.hash(key) |> Base.encode16(case: :lower)
      refute credential.key_digest == key

      listed = conn |> through_proxy("ada@example.test") |> get("/devices") |> json_response(200)
      assert [%{"id" => ^id, "holds_key" => true} = entry] = listed["devices"]
      refute Map.has_key?(entry, "key")
      refute Jason.encode!(listed) =~ key
    end

    test "the key identifies its principal on the surface", %{conn: conn, key: key} do
      principal = Principals.principal_for(issuer(), "ada@example.test")

      body =
        conn
        |> via_proxy()
        |> get("/rest/tokenInfo", %{"apiKey" => key, "f" => "json"})
        |> json_response(200)

      assert body["subsonic-response"]["tokenInfo"]["username"] == principal.id
    end

    test "a revoked device's key is refused with error 44", %{conn: conn, key: key, device_id: id} do
      conn |> through_proxy("ada@example.test") |> delete("/devices/#{id}") |> json_response(200)

      assert error_code(conn, %{"apiKey" => key}) == 44
    end

    test "a retired principal's key is refused with error 44", %{conn: conn, key: key} do
      {:ok, admin} = Principals.create_principal(%{role: "administrator"})
      principal = Principals.principal_for(issuer(), "ada@example.test")
      {:ok, _} = Administration.retire_principal(admin, principal.id)

      assert error_code(conn, %{"apiKey" => key}) == 44
    end

    test "another principal cannot revoke the credential", %{conn: conn, device_id: id} do
      principal = Principals.principal_for(issuer(), "ada@example.test")

      assert conn
             |> through_proxy("grace@example.test")
             |> delete("/devices/#{id}")
             |> json_response(404)

      assert Repo.get_by!(DeviceCredential, device_id: id, principal_id: principal.id).revoked_at ==
               nil
    end
  end

  describe "1. The native API refuses a client key" do
    test "a key with no forward-authenticated identity reaches nothing", %{conn: conn, key: key} do
      assert conn |> via_proxy() |> get("/devices", %{"apiKey" => key}) |> response(401)
    end
  end

  describe "3. The surface refuses a request that did not come through the proxy" do
    test "a valid key without the proxy's assertion is not read", %{conn: conn, key: key} do
      response = conn |> get("/rest/ping", %{"apiKey" => key}) |> response(401)
      assert response =~ "did not come through the authenticating proxy"
    end
  end

  describe "4. Passwords, tokens, mixed and invalid keys are refused" do
    test "a password is error 42, and says where a key comes from", %{conn: conn} do
      assert error_code(conn, %{"u" => "ada", "p" => "secret"}) == 42

      body =
        conn
        |> via_proxy()
        |> get("/rest/ping", %{"u" => "ada", "p" => "secret", "f" => "json"})
        |> json_response(200)

      assert body["subsonic-response"]["error"]["helpUrl"] == "https://pluteus.test/devices"
    end

    test "a salted token is error 42", %{conn: conn} do
      assert error_code(conn, %{"u" => "ada", "t" => "abc", "s" => "salt"}) == 42
    end

    test "u with apiKey is error 43", %{conn: conn, key: key} do
      assert error_code(conn, %{"u" => "ada", "apiKey" => key}) == 43
    end

    test "an unknown key is error 44", %{conn: conn} do
      assert error_code(conn, %{"apiKey" => "pk_not-a-key"}) == 44
    end

    test "no key is error 10", %{conn: conn} do
      assert error_code(conn, %{}) == 10
    end
  end

  describe "a key may arrive in a header, for a client that has no field for one" do
    test "the header authenticates, and a password beside it is ignored", %{conn: conn, key: key} do
      principal = Principals.principal_for(issuer(), "ada@example.test")

      body =
        conn
        |> via_proxy()
        |> put_req_header("x-api-key", key)
        |> get("/rest/tokenInfo", %{"u" => "ada", "p" => "whatever", "f" => "json"})
        |> json_response(200)

      assert body["subsonic-response"]["status"] == "ok"
      assert body["subsonic-response"]["tokenInfo"]["username"] == principal.id
    end

    test "an unknown key in the header is error 44", %{conn: conn} do
      assert conn
             |> via_proxy()
             |> put_req_header("x-api-key", "pk_not-a-key")
             |> get("/rest/ping", %{"f" => "json"})
             |> json_response(200)
             |> get_in(["subsonic-response", "error", "code"]) == 44
    end

    test "two keys in the header are conflicting mechanisms", %{conn: conn, key: key} do
      assert conn
             |> via_proxy()
             |> put_req_header("x-api-key", key)
             |> Plug.Conn.prepend_req_headers([{"x-api-key", key}])
             |> get("/rest/ping", %{"f" => "json"})
             |> json_response(200)
             |> get_in(["subsonic-response", "error", "code"]) == 43
    end

    test "the native API still refuses a key, header or not", %{conn: conn, key: key} do
      assert conn
             |> via_proxy()
             |> put_req_header("x-api-key", key)
             |> get("/works")
             |> response(401)
    end
  end

  describe "14. Every response carries the OpenSubsonic fields, in XML or JSON" do
    test "XML by default", %{conn: conn, key: key} do
      body = conn |> via_proxy() |> get("/rest/ping", %{"apiKey" => key}) |> response(200)

      assert body =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
      assert body =~ ~s(<subsonic-response openSubsonic="true" serverVersion=)

      assert body =~
               ~s(status="ok" type="pluteus" version="1.16.1" xmlns="http://subsonic.org/restapi"/>)
    end

    test "JSON on f=json, and the .view suffix and form POST both reach the endpoint",
         %{conn: conn, key: key} do
      for request <- [
            fn c -> get(c, "/rest/ping.view", %{"apiKey" => key, "f" => "json"}) end,
            fn c -> post(c, "/rest/ping", %{"apiKey" => key, "f" => "json"}) end
          ] do
        body = conn |> via_proxy() |> request.() |> json_response(200)

        assert %{
                 "status" => "ok",
                 "version" => "1.16.1",
                 "type" => "pluteus",
                 "openSubsonic" => true,
                 "serverVersion" => _
               } = body["subsonic-response"]
      end
    end
  end

  describe "15. The extensions advertised are the four this deployment implements" do
    @tag :criterion_15_awaits_spec_08
    test "four, each at version 1", %{conn: conn, key: key} do
      # spec-07 §6.2 names six. The other two, `transcoding` and `transcodeOffset`,
      # describe `getTranscodeDecision` and `getTranscodeStream`, which are spec-08's and
      # are not built — and §6.2 forbids advertising an extension that is not there.
      #
      # So criterion 15 does not hold yet, and this asserts what the deployment does
      # rather than what the criterion says. A test claiming "exactly spec-07's" while
      # asserting four of six is worse than an open gap, because it reads as coverage.
      body =
        conn
        |> via_proxy()
        |> get("/rest/getOpenSubsonicExtensions", %{"apiKey" => key, "f" => "json"})
        |> json_response(200)

      assert Enum.sort_by(body["subsonic-response"]["openSubsonicExtensions"], & &1["name"]) == [
               %{"name" => "apiKeyAuthentication", "versions" => [1]},
               %{"name" => "formPost", "versions" => [1]},
               %{"name" => "indexBasedQueue", "versions" => [1]},
               %{"name" => "songLyrics", "versions" => [1]}
             ]
    end
  end

  describe "spec-06 17. A key identifies its principal only on the exempt surface, only through the proxy, and not once its device is revoked" do
    test "all three conditions together, so no one of them carries the rule alone",
         %{conn: conn, key: key, device_id: id} do
      principal = Principals.principal_for(issuer(), "ada@example.test")

      # On the exempt surface, through the proxy: the key names its principal.
      body =
        conn
        |> via_proxy()
        |> get("/rest/tokenInfo", %{"apiKey" => key, "f" => "json"})
        |> json_response(200)

      assert body["subsonic-response"]["tokenInfo"]["username"] == principal.id

      # The same key off the exempt surface reaches nothing, whatever it names.
      assert get(conn, "/works", %{"apiKey" => key}).status == 401

      # And on the exempt surface without the proxy's assertion it is not read, so the
      # key is never the whole of a request's authentication.
      assert conn |> get("/rest/ping", %{"apiKey" => key}) |> Map.fetch!(:status) == 401

      # Revoking the device ends it, without touching the principal.
      conn |> through_proxy("ada@example.test") |> delete("/devices/#{id}") |> json_response(200)

      assert error_code(conn, %{"apiKey" => key}) == 44
      assert Principals.principal_for(issuer(), "ada@example.test").id == principal.id
    end
  end

  describe "16. An endpoint not provided answers error 0 naming it" do
    test "podcasts are not provided, and say so", %{conn: conn, key: key} do
      body =
        conn
        |> via_proxy()
        |> get("/rest/getPodcasts", %{"apiKey" => key, "f" => "json"})
        |> json_response(200)

      assert %{"status" => "failed", "error" => %{"code" => 0, "message" => message}} =
               body["subsonic-response"]

      assert message =~ "getPodcasts"
    end
  end

  defp error_code(conn, params) do
    body =
      conn |> via_proxy() |> get("/rest/ping", Map.put(params, "f", "json")) |> json_response(200)

    %{"status" => "failed", "error" => %{"code" => code}} = body["subsonic-response"]
    code
  end
end
