defmodule PluteusWeb.Device do
  @moduledoc """
  Which device the browser reaching the interface is ([spec-01] §11.4).

  A position, a play queue and an event are keyed by device, so a surface that can play
  anything needs one before it renders the control that would. The browser profile is the
  device, as it already is for §4.4's surface declaration, and a cookie beside that one
  carries which.

  The device is assigned, and so is why there is none. A principal who revoked this
  browser's enrolment has it stay revoked, and the transport says so rather than silently
  taking a second credential — which would undo the revocation and report nothing.

  ## The label is the client's own statement, and the address the proxy's

  A device carries a label naming it (spec-07 §3.2) and there is no route to rename one,
  so it is derived rather than asked for. Where the client sends Client Hints the label is
  what the client says about itself, which is structured and needs no parsing. Where it
  does not, the last product token of the user agent is what browsers conventionally put
  there — a convention and not a guarantee, which is why a client that states nothing
  usable is labelled as having stated nothing rather than guessed at.

  The address comes from `x-real-ip`, which the proxy sets from the connection it accepted.
  Not the first entry of `x-forwarded-for`: a browser may send that header itself and the
  proxy appends to it, so its leading entries are the client's own claim. `x-real-ip` is
  set rather than added, so it is the one the proxy observed.

  A label is a display string and never an identifier, so an address that later changes
  makes a label stale and nothing else.
  """

  @behaviour Plug

  import Plug.Conn

  alias Pluteus.Principals

  @cookie "pluteus_device"

  # Three years, as the surface declaration keeps: the same browser profile is the same
  # device until somebody says otherwise.
  @age 94_608_000

  # The brands Client Hints pad the list with, so that a client reading it cannot assume
  # the list is only real names. Theirs are the ones that are not these.
  @greased ["Not.A/Brand", "Not;A=Brand", "Not)A;Brand", "Not=A?Brand", "Not A;Brand"]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{assigns: %{principal: principal}} = conn, _opts) do
    case Principals.device_for_browser(principal, claimed(conn), label(conn)) do
      {:ok, device} ->
        conn |> assign(:device_id, device.id) |> remember(device)

      {:revoked, device} ->
        conn
        |> assign(:device_id, nil)
        |> assign(:device_revoked, device.label)
    end
  end

  @doc """
  The name of the cookie the device is remembered in.
  """
  @spec cookie() :: String.t()
  def cookie, do: @cookie

  defp claimed(conn) do
    conn = fetch_cookies(conn)

    case Ecto.UUID.cast(conn.cookies[@cookie] || "") do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp remember(conn, device) do
    put_resp_cookie(conn, @cookie, device.id,
      max_age: @age,
      same_site: "Lax",
      http_only: true
    )
  end

  defp label(conn) do
    "#{client(conn)} at #{address(conn)}"
  end

  defp client(conn) do
    case {brand(conn), header(conn, "sec-ch-ua-platform")} do
      {nil, _platform} -> stated(conn)
      {brand, nil} -> brand
      {brand, platform} -> "#{brand} on #{unquoted(platform)}"
    end
  end

  # One entry of `sec-ch-ua` is `"Brand";v="140"`, and the padding entries are there to
  # stop a reader trusting the shape of the list.
  defp brand(conn) do
    with hint when is_binary(hint) <- header(conn, "sec-ch-ua") do
      hint
      |> String.split(",")
      |> Enum.map(&(&1 |> String.split(";") |> hd() |> String.trim() |> unquoted()))
      |> Enum.find(&(&1 not in @greased and &1 != ""))
    end
  end

  # The convention, where the client offers nothing structured: a user agent ends with the
  # product token naming the browser. A client sending neither has said nothing this can
  # name it by, and a made-up name would be worse than saying so.
  defp stated(conn) do
    case header(conn, "user-agent") do
      nil ->
        "A client naming itself nothing"

      agent ->
        agent
        |> String.split()
        |> Enum.reject(&String.starts_with?(&1, "("))
        |> List.last()
        |> case do
          nil -> "A client naming itself nothing"
          token -> token
        end
    end
  end

  defp address(conn) do
    header(conn, "x-real-ip") || conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  defp header(conn, name) do
    case get_req_header(conn, name) do
      [value | _rest] -> value
      [] -> nil
    end
  end

  defp unquoted(value), do: String.trim(value, "\"")
end
