defmodule PluteusWeb.DeviceController do
  @moduledoc """
  A principal's own devices and their client keys (spec-07 §3.2, spec-06 §4),
  reached only through forward authentication.

  Minting answers with the key once. Listing never shows a key, since none is
  kept to show.
  """

  use PluteusWeb, :controller

  alias Pluteus.Administration
  alias Pluteus.Principals
  alias PluteusWeb.Problem

  def create(conn, %{"label" => label}) when is_binary(label) and label != "" do
    {:ok, %{device: device, key: key}} = Principals.mint_key(conn.assigns.principal.id, label)

    conn
    |> put_status(201)
    |> json(%{"device" => present(device), "key" => key})
  end

  def create(conn, _params) do
    Problem.send(conn, 400, %{
      type: Problem.type("invalid-request"),
      title: "invalid-request",
      detail: "a device needs a label naming it"
    })
  end

  def index(conn, _params) do
    json(conn, %{
      "devices" => Enum.map(Principals.devices_of(conn.assigns.principal.id), &present/1)
    })
  end

  def delete(conn, %{"id" => id}) do
    case Administration.revoke_device(conn.assigns.principal, id) do
      {:ok, device} ->
        json(conn, %{"device" => present(device)})

      {:error, :not_permitted} ->
        Problem.send(conn, 404, %{
          type: Problem.type("not-found"),
          title: "not-found",
          detail: "no such device"
        })
    end
  end

  defp present(device) do
    %{
      "id" => device.id,
      "label" => device.label,
      "bound_at" => device.bound_at,
      "revoked_at" => device.revoked_at,
      "holds_key" => not is_nil(device.key_digest)
    }
  end
end
