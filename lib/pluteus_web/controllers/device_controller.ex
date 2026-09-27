defmodule PluteusWeb.DeviceController do
  @moduledoc """
  The credentials a principal holds on devices, and their client keys
  (spec-07 §3.2, spec-06 §4), reached only through forward authentication.

  What is listed and revoked is a credential, not a device: §4.1 lets a device
  hold one per principal and [spec-10] criterion 55 requires each be revocable
  without disturbing another principal's enrolment on the same screen. So the
  resource keeps its `/devices` path, which spec-07 §4.1 names, and each entry
  names its device and what that credential grants.

  Minting answers with the key once. Listing never shows a key, since none is
  kept to show.

  A second principal enrols on a device that already exists by naming it rather
  than labelling it again: the label is the device's, and a label given alongside a
  device is two conflicting statements about one screen's name, which is refused
  rather than resolved.
  """

  use PluteusWeb, :controller

  alias Pluteus.Administration
  alias Pluteus.Authorization
  alias Pluteus.Principals
  alias Pluteus.Principals.Device
  alias Pluteus.Repo
  alias PluteusWeb.Problem

  def create(conn, %{"device_id" => _, "label" => _}) do
    invalid(conn, "a device is named when it is first enrolled, not again")
  end

  def create(conn, %{"device_id" => device_id}) when is_binary(device_id) do
    principal = conn.assigns.principal

    case Ecto.UUID.cast(device_id) do
      {:ok, _} -> enrol_on(conn, principal, Repo.get(Device, device_id))
      :error -> invalid(conn, "device_id is not an identifier")
    end
  end

  def create(conn, %{"label" => label}) when is_binary(label) and label != "" do
    principal = conn.assigns.principal

    {:ok, minted} =
      Principals.mint_key(principal.id, label, Authorization.grantable_to(principal))

    minted(conn, minted)
  end

  def create(conn, _params), do: invalid(conn, "a device needs a label naming it")

  def index(conn, _params) do
    json(conn, %{
      "devices" => Enum.map(Principals.credentials_of(conn.assigns.principal.id), &present/1)
    })
  end

  # Without a `principal_id` the principal revokes its own credential. Naming
  # another's is the Administrator power §6.1's row carries, and `revoke_credential`
  # refuses it to anyone else.
  def delete(conn, %{"id" => id} = params) do
    actor = conn.assigns.principal
    subject = Map.get(params, "principal_id", actor.id)

    case Administration.revoke_credential(actor, id, subject) do
      {:ok, credential} ->
        json(conn, %{"device" => present(Repo.preload(credential, :device))})

      {:error, reason} when reason in [:not_permitted, :no_such_credential] ->
        Problem.send(conn, 404, %{
          type: Problem.type("not-found"),
          title: "not-found",
          detail: "no such device"
        })
    end
  end

  defp enrol_on(conn, _principal, nil), do: invalid(conn, "no such device")

  defp enrol_on(conn, principal, %Device{} = device) do
    case Principals.mint_key_for(principal.id, device, Authorization.grantable_to(principal)) do
      {:ok, minted} -> minted(conn, minted)
      {:error, _changeset} -> invalid(conn, "this principal is already enrolled on that device")
    end
  end

  defp minted(conn, %{device: device, credential: credential, key: key}) do
    conn
    |> put_status(201)
    |> json(%{"device" => present(%{credential | device: device}), "key" => key})
  end

  defp invalid(conn, detail) do
    Problem.send(conn, 400, %{
      type: Problem.type("invalid-request"),
      title: "invalid-request",
      detail: detail
    })
  end

  # The grant is shown, because a credential refused an operation is only legible
  # to whoever enrolled the device if they can see what it was given.
  defp present(credential) do
    %{
      "id" => credential.device_id,
      "label" => credential.device.label,
      "player_number" => credential.device.player_number,
      "bound_at" => credential.bound_at,
      "revoked_at" => credential.revoked_at,
      "holds_key" => not is_nil(credential.key_digest),
      "granted" => Enum.map(credential.granted, &to_string/1)
    }
  end
end
