defmodule PluteusWeb.ClientKeysTest do
  @moduledoc """
  Client keys and the OpenSubsonic envelope: spec-07 §3, §6.1, §6.2 and
  criteria 1 to 5 and 14 to 16.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Administration
  alias Pluteus.Principals
  alias Pluteus.Principals.Device
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
      device = Repo.get!(Device, id)

      assert String.starts_with?(key, "pk_")
      assert device.key_digest == :sha256 |> :crypto.hash(key) |> Base.encode16(case: :lower)
      refute device.key_digest == key

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

    test "another principal cannot revoke the device", %{conn: conn, device_id: id} do
      assert conn
             |> through_proxy("grace@example.test")
             |> delete("/devices/#{id}")
             |> json_response(404)

      assert Repo.get!(Device, id).revoked_at == nil
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

  describe "15. The extensions advertised are exactly spec-07's" do
    test "four, each at version 1", %{conn: conn, key: key} do
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
