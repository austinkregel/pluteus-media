defmodule Pluteus.Administration do
  @moduledoc """
  The operations spec-06 §6.1 reserves for an Administrator, and the one it
  grants a Member over itself.

  None of these is a catalog write. Each acts on principals or devices,
  and each writes an audit record naming the actor, the affected principal, the
  operation and the time, whether it succeeded, was refused, or raised
  (spec-06 §6.6). A raised error is recorded and then raised again, never
  swallowed.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Administration.AuditRecord
  alias Pluteus.Authorization
  alias Pluteus.Lifecycle
  alias Pluteus.Lifecycle.Recycling
  alias Pluteus.Principals
  alias Pluteus.Principals.DeviceCredential
  alias Pluteus.Principals.Principal
  alias Pluteus.Repo

  @doc """
  Makes a principal an Administrator or a Member.

  The identity provider decides who is a member at all; this decides who among
  them administers the deployment. The System role is the deployment's own and
  is never assigned.
  """
  @spec set_role(Principal.t(), Ecto.UUID.t(), String.t()) ::
          {:ok, Principal.t()} | {:error, term()}
  def set_role(%Principal{} = actor, principal_id, role) do
    audited(actor, "set_role", principal_id, fn ->
      with :ok <- permit(actor, :set_role),
           :ok <- assignable(role) do
        Principal
        |> Repo.get!(principal_id)
        |> Principal.changeset(%{role: role})
        |> Repo.update()
      end
    end)
  end

  @doc """
  Removes a principal from the trust boundary. The principal is kept, retired,
  so its events and the catalog writes it made stay attributable.
  """
  @spec retire_principal(Principal.t(), Ecto.UUID.t(), DateTime.t()) ::
          {:ok, Principal.t()} | {:error, term()}
  def retire_principal(%Principal{} = actor, principal_id, now \\ DateTime.utc_now()) do
    audited(actor, "retire_principal", principal_id, fn ->
      with :ok <- permit(actor, :retire_principal) do
        Principal
        |> Repo.get!(principal_id)
        |> Ecto.Changeset.change(retired_at: now)
        |> Repo.update()
      end
    end)
  end

  @doc """
  Maps a further `(issuer, subject)` onto a principal (spec-06 §3.3).

  This grants whoever holds the new identity the principal's whole history, so
  who may do it is narrow. An Administrator may map onto anyone. A Member may
  map onto itself only while it is authenticated, now, through a mapping it
  already has — the case of preparing for a provider migration. Nobody else may.
  `authenticated_as` is the identity the actor's current request arrived under.
  """
  @spec add_identity(
          Principal.t(),
          Ecto.UUID.t(),
          {String.t(), String.t()},
          {String.t(), String.t()}
        ) ::
          {:ok, term()} | {:error, term()}
  def add_identity(%Principal{} = actor, principal_id, {issuer, subject}, authenticated_as) do
    audited(actor, "add_identity", principal_id, fn ->
      with :ok <- permit_identity(actor, principal_id, authenticated_as) do
        Principals.bind_identity(principal_id, issuer, subject)
      end
    end)
  end

  @doc """
  Revokes one principal's credential on one device. A principal may revoke its
  own; an Administrator anyone's.

  The pair names the credential, because a device may hold several and §4.1
  requires each be separately revocable: revoking one leaves the others usable.
  Both identifiers are arguments for that reason — there is no longer one
  principal a device could be said to belong to.
  """
  @spec revoke_credential(Principal.t(), Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) ::
          {:ok, DeviceCredential.t()} | {:error, term()}
  def revoke_credential(
        %Principal{} = actor,
        device_id,
        principal_id,
        now \\ DateTime.utc_now()
      ) do
    audited(actor, "revoke_device", principal_id, fn ->
      with :ok <- permit_credential(actor, principal_id),
           %DeviceCredential{} = credential <- Principals.credential_on(principal_id, device_id) do
        credential
        |> DeviceCredential.revocation_changeset(%{revoked_at: now, revoked_by: actor.id})
        |> Repo.update()
      else
        nil -> {:error, :no_such_credential}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @doc """
  Empties another principal's deletion before its window closes. It destroys
  the window that makes the recycle bin a safety net, which is why only an
  Administrator may (spec-01 §14.1).
  """
  @spec empty_deletion(Principal.t(), Ecto.UUID.t(), DateTime.t()) ::
          {:ok, map()} | {:error, term()}
  def empty_deletion(%Principal{} = actor, recycling_id, now \\ DateTime.utc_now()) do
    recycling = Repo.get!(Recycling, recycling_id)

    audited(actor, "empty_deletion", recycling.recycled_by, fn ->
      with :ok <- permit(actor, :empty_anothers_deletion) do
        Lifecycle.purge(recycling, now)
      end
    end)
  end

  @doc """
  Every audit record, most recent first.
  """
  @spec audit_trail() :: [AuditRecord.t()]
  def audit_trail do
    Repo.all(from a in AuditRecord, order_by: [desc: a.occurred_at, desc: a.inserted_at])
  end

  defp assignable(role) when role in ["administrator", "member"], do: :ok
  defp assignable(_role), do: {:error, :role_not_assignable}

  defp permit(actor, power) do
    if Authorization.may?(actor, power), do: :ok, else: {:error, :not_permitted}
  end

  defp permit_identity(%Principal{} = actor, principal_id, authenticated_as) do
    cond do
      Authorization.may?(actor, :add_identity_to_another) ->
        :ok

      actor.role == "member" and actor.id == principal_id and
          Principals.authenticates_as?(authenticated_as, actor.id) ->
        :ok

      true ->
        {:error, :not_permitted}
    end
  end

  defp permit_credential(%Principal{id: id}, id), do: :ok
  defp permit_credential(actor, _principal_id), do: permit(actor, :revoke_anothers_device)

  # The record is written after the operation, outside its transaction, so a
  # failure that rolled the operation back is still recorded. A raise is
  # recorded and raised again.
  defp audited(actor, operation, subject_id, fun) do
    result =
      try do
        fun.()
      rescue
        exception ->
          record!(actor, operation, subject_id, "raised: " <> Exception.message(exception))
          reraise exception, __STACKTRACE__
      end

    case result do
      {:ok, _value} ->
        record!(actor, operation, subject_id, nil)

      {:error, reason} ->
        record!(actor, operation, subject_id, inspect(reason))
    end

    result
  end

  defp record!(actor, operation, subject_id, reason) do
    Repo.insert!(%AuditRecord{
      actor_id: actor.id,
      subject_id: subject_id,
      operation: operation,
      outcome: if(is_nil(reason), do: :succeeded, else: :failed),
      reason: reason,
      occurred_at: DateTime.utc_now()
    })
  end
end
