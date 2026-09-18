defmodule Pluteus.Principals do
  @moduledoc """
  Reads and writes over the identities that use the system.

  Nothing outside this module refers to an `(issuer, subject)` composite. §10.1
  requires every reference to be to the principal's locally minted identifier,
  which is what makes a provider migration a remapping rather than a new
  principal with an empty history.
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Pluteus.Catalog.Res
  alias Pluteus.Principals.Device
  alias Pluteus.Principals.Identity
  alias Pluteus.Principals.Principal
  alias Pluteus.Repo

  @doc """
  Mints a principal under a role.

  Pass `:person_id` to link it to the LRM person it corresponds to. Leave it out
  for the deployment itself, which acts as a principal and is nobody.
  """
  @spec create_principal(map()) :: {:ok, Principal.t()} | {:error, Ecto.Changeset.t() | atom()}
  def create_principal(attrs) do
    Multi.new()
    |> Multi.run(:person_kind, fn repo, _changes -> person_kind(repo, attrs[:person_id]) end)
    |> Multi.insert(:principal, fn %{person_kind: person_kind} ->
      Principal.changeset(%Principal{}, put_person_kind(attrs, person_kind))
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{principal: principal}} -> {:ok, principal}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Records that a provider knows this principal by an `(issuer, subject)` pair.

  A principal may hold several. An issuer change is a second pair against the
  same principal, not a second principal.
  """
  @spec bind_identity(Ecto.UUID.t(), String.t(), String.t()) ::
          {:ok, Identity.t()} | {:error, Ecto.Changeset.t()}
  def bind_identity(principal_id, issuer, subject) do
    %Identity{}
    |> Identity.changeset(%{principal_id: principal_id, issuer: issuer, subject: subject})
    |> Repo.insert()
  end

  @doc """
  Moves an existing binding to a new issuer.

  §10.1 names this repair directly: the composite changed, the principal did
  not, so the mapping is rewritten and every reference to the principal — events
  included — is untouched because none of them held the composite.
  """
  @spec rebind_issuer(String.t(), String.t(), String.t()) :: non_neg_integer()
  def rebind_issuer(old_issuer, new_issuer, subject) do
    {count, _} =
      Repo.update_all(
        from(i in Identity, where: i.issuer == ^old_issuer and i.subject == ^subject),
        set: [issuer: new_issuer, updated_at: DateTime.utc_now()]
      )

    count
  end

  @doc """
  The principal an identity the provider has admitted belongs to, created as a
  Member the first time the identity arrives (spec-06 §6.1).

  Two first requests from one person can arrive together. The identity pair is
  unique, so the second insert is refused, and the principal the first created
  is the answer to both.
  """
  @spec admit(String.t(), String.t()) :: Principal.t()
  def admit(issuer, subject) do
    case principal_for(issuer, subject) do
      %Principal{} = principal -> principal
      nil -> first_arrival(issuer, subject)
    end
  end

  defp first_arrival(issuer, subject) do
    case Repo.transaction(fn -> create_member(issuer, subject) end) do
      {:ok, principal} -> principal
      {:error, :identity_taken} -> principal_for(issuer, subject)
    end
  end

  defp create_member(issuer, subject) do
    {:ok, principal} = create_principal(%{role: "member"})

    case bind_identity(principal.id, issuer, subject) do
      {:ok, _identity} ->
        principal

      {:error, changeset} ->
        if taken?(changeset),
          do: Repo.rollback(:identity_taken),
          else: raise(Ecto.InvalidChangesetError, action: :insert, changeset: changeset)
    end
  end

  defp taken?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_message, opts}} -> opts[:constraint] == :unique end)
  end

  @doc """
  The principal a provider's `(issuer, subject)` pair names, if any.
  """
  @spec principal_for(String.t(), String.t()) :: Principal.t() | nil
  def principal_for(issuer, subject) do
    Repo.one(
      from p in Principal,
        join: i in Identity,
        on: i.principal_id == p.id,
        where: i.issuer == ^issuer and i.subject == ^subject
    )
  end

  @spec get_principal(Ecto.UUID.t()) :: Principal.t() | nil
  def get_principal(id), do: Repo.get(Principal, id)

  @doc """
  The deployment's own principal, minted at onboarding (spec-06 §6.5).
  Raises before onboarding, when there is none: whatever asked has nothing to
  act as.
  """
  @spec system!() :: Principal.t()
  def system!, do: Repo.get_by!(Principal, role: "system")

  @doc """
  Whether an `(issuer, subject)` pair currently authenticates as the principal.
  """
  @spec authenticates_as?({String.t(), String.t()}, Ecto.UUID.t()) :: boolean()
  def authenticates_as?({issuer, subject}, principal_id) do
    case principal_for(issuer, subject) do
      %Principal{id: ^principal_id} -> true
      _other -> false
    end
  end

  @doc """
  Binds a device to a principal (spec-06 §4).
  """
  @spec bind_device(Ecto.UUID.t(), String.t(), DateTime.t()) ::
          {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def bind_device(principal_id, label, now \\ DateTime.utc_now()) do
    %Device{}
    |> Device.changeset(%{principal_id: principal_id, label: label, bound_at: now})
    |> Repo.insert()
  end

  @spec devices_of(Ecto.UUID.t()) :: [Device.t()]
  def devices_of(principal_id) do
    Repo.all(from d in Device, where: d.principal_id == ^principal_id, order_by: d.bound_at)
  end

  @doc """
  Every `(issuer, subject)` pair bound to a principal.
  """
  @spec identities_of(Ecto.UUID.t()) :: [Identity.t()]
  def identities_of(principal_id) do
    Repo.all(from i in Identity, where: i.principal_id == ^principal_id)
  end

  defp person_kind(_repo, nil), do: {:ok, nil}

  defp person_kind(repo, person_id) do
    case repo.get(Res, person_id) do
      nil -> {:error, :no_such_res}
      %Res{kind: kind} -> {:ok, kind}
    end
  end

  defp put_person_kind(attrs, nil), do: attrs
  defp put_person_kind(attrs, person_kind), do: Map.put(attrs, :person_kind, person_kind)
end
