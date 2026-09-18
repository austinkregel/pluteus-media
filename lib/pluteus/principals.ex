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
