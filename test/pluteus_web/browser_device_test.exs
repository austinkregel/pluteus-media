defmodule PluteusWeb.BrowserDeviceTest do
  @moduledoc """
  The device a browser reaching the interface is (spec-06 §4.1, [spec-01] §11.4).

  A position, a queue and an event are keyed by device, and the composite foreign key
  admits only a device the principal holds a credential on, so the interface can record
  nothing about where anybody is until this has answered. What is asserted here is that it
  answers once per browser profile, that two principals sharing one are one screen, and
  that a revocation stays done.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Principals.Device, as: DeviceRow
  alias Pluteus.Principals.DeviceCredential
  alias Pluteus.Repo
  alias PluteusWeb.Device

  setup %{conn: conn} do
    %{conn: conn |> through_proxy(a_subject()) |> on_a_surface()}
  end

  describe "spec-06 §4.1. A browser profile is a device the principal holds a credential on" do
    test "a browser carrying no device is enrolled, and told which it is", %{conn: conn} do
      answered = get(conn, ~p"/everything")

      assert [device] = Repo.all(DeviceRow)
      assert answered.resp_cookies[Device.cookie()].value == device.id
    end

    test "the credential carries no key, so no key can reach it", %{conn: conn} do
      # A browser authenticates through the proxy. A credential with a key would be a
      # second way in that nobody minted and nobody could revoke knowingly.
      get(conn, ~p"/everything")

      assert [%DeviceCredential{key_digest: nil, revoked_at: nil}] = Repo.all(DeviceCredential)
    end

    test "the same browser returning is the same device", %{conn: conn} do
      first = get(conn, ~p"/everything")

      conn
      |> Plug.Test.put_req_cookie(Device.cookie(), first.resp_cookies[Device.cookie()].value)
      |> get(~p"/everything")

      assert [_one] = Repo.all(DeviceRow)
    end

    test "two principals sharing a browser profile are one screen with two credentials",
         %{conn: conn} do
      # §4.1's own case, and why `player_number` belongs to the device: one television
      # enrolled for two people is one player.
      first = get(conn, ~p"/everything")
      remembered = first.resp_cookies[Device.cookie()].value

      Phoenix.ConnTest.build_conn()
      |> through_proxy(a_subject("bob"))
      |> on_a_surface()
      |> Plug.Test.put_req_cookie(Device.cookie(), remembered)
      |> get(~p"/everything")

      assert [_one] = Repo.all(DeviceRow)
      assert [_ada, _bob] = Repo.all(DeviceCredential)
    end

    test "a cookie naming nothing this deployment holds enrols rather than raising",
         %{conn: conn} do
      # A cookie is the browser's to write, so it may hold anything at all.
      answered =
        conn
        |> Plug.Test.put_req_cookie(Device.cookie(), "not an identifier")
        |> get(~p"/everything")

      assert answered.status == 200
      assert [device] = Repo.all(DeviceRow)
      assert answered.resp_cookies[Device.cookie()].value == device.id
    end
  end

  describe "spec-06 §4.1. A revoked credential stays revoked" do
    test "the browser is left with no device, and why is carried", %{conn: conn} do
      first = get(conn, ~p"/everything")
      remembered = first.resp_cookies[Device.cookie()].value

      [credential] = Repo.all(DeviceCredential)

      {:ok, _} =
        credential
        |> Ecto.Changeset.change(
          revoked_at: DateTime.utc_now(),
          revoked_by: credential.principal_id
        )
        |> Repo.update()

      again =
        conn
        |> Plug.Test.put_req_cookie(Device.cookie(), remembered)
        |> get(~p"/everything")

      assert again.assigns.device_id == nil
      assert again.assigns.device_revoked =~ "at "
      assert [_only_the_revoked_one] = Repo.all(DeviceCredential)
    end
  end

  describe "spec-07 §3.2. The label names the client and where it reached from" do
    test "a client sending hints is named by what it says about itself", %{conn: conn} do
      conn
      |> Plug.Conn.put_req_header("sec-ch-ua", ~s|"Not=A?Brand";v="24", "Chromium";v="140"|)
      |> Plug.Conn.put_req_header("sec-ch-ua-platform", ~s|"Linux"|)
      |> Plug.Conn.put_req_header("x-real-ip", "192.168.1.42")
      |> get(~p"/everything")

      assert [%DeviceRow{label: "Chromium on Linux at 192.168.1.42"}] = Repo.all(DeviceRow)
    end

    test "a client sending none is named by the convention its agent follows", %{conn: conn} do
      agent = "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"

      conn
      |> Plug.Conn.put_req_header("user-agent", agent)
      |> Plug.Conn.put_req_header("x-real-ip", "192.168.1.43")
      |> get(~p"/everything")

      assert [%DeviceRow{label: "Firefox/140.0 at 192.168.1.43"}] = Repo.all(DeviceRow)
    end

    test "a client stating nothing usable is said to have stated nothing", %{conn: conn} do
      # A made-up name would read as something the client claimed.
      conn
      |> Plug.Conn.put_req_header("x-real-ip", "192.168.1.44")
      |> get(~p"/everything")

      assert [%DeviceRow{label: label}] = Repo.all(DeviceRow)
      assert label == "A client naming itself nothing at 192.168.1.44"
    end

    test "the address is the one the proxy observed, not the one the browser claimed",
         %{conn: conn} do
      # A browser may send `x-forwarded-for` itself and the proxy appends to it, so its
      # leading entries are the client's own claim.
      conn
      |> Plug.Conn.put_req_header("x-forwarded-for", "10.0.0.1, 192.168.1.45")
      |> Plug.Conn.put_req_header("x-real-ip", "192.168.1.45")
      |> get(~p"/everything")

      assert [%DeviceRow{label: label}] = Repo.all(DeviceRow)
      assert label =~ "192.168.1.45"
      refute label =~ "10.0.0.1"
    end
  end

  describe "A device is enrolled only where a surface renders" do
    test "a device that has declared no surface is sent away before it is enrolled" do
      asked = get(through_proxy(Phoenix.ConnTest.build_conn(), a_subject()), ~p"/everything")

      assert redirected_to(asked) =~ "/surface"
      assert Repo.all(DeviceRow) == []
    end

    test "a request carrying no principal enrols nothing" do
      refused = get(on_a_surface(Phoenix.ConnTest.build_conn()), ~p"/everything")

      assert refused.status in 401..403
      assert Repo.all(DeviceRow) == []
    end
  end
end
