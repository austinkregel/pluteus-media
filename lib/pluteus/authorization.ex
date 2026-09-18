defmodule Pluteus.Authorization do
  @moduledoc """
  What a principal may do (spec-06 §6.1).

  Members are peers over the catalog: nobody owns a work, and an Administrator
  holds no more authority over what the household holds than a Member does.
  The Administrator's additional powers act on principals, devices and grants.
  A guest reads what it has been granted and writes nothing to the catalog; the
  database refuses a guest's catalog write whatever this module says, so this is
  the explanation of the rule and not its only enforcement.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Principals.GuestGrant
  alias Pluteus.Principals.Principal
  alias Pluteus.Repo

  @administration ~w(
    create_principal retire_principal grant_guest revoke_guest_grant
    add_identity_to_another revoke_anothers_device empty_anothers_deletion
  )a

  @doc """
  Whether a principal holds an administrative power. Only an Administrator does.
  """
  @spec may?(Principal.t(), atom()) :: boolean()
  def may?(%Principal{role: "administrator", retired_at: nil}, power)
      when power in @administration,
      do: true

  def may?(%Principal{}, power) when power in @administration, do: false

  @doc """
  Whether a principal may read a res. A guest reads only what it was granted.
  """
  @spec may_read?(Principal.t(), Ecto.UUID.t()) :: boolean()
  def may_read?(%Principal{role: "guest", id: principal_id}, res_id) do
    Repo.exists?(
      from g in GuestGrant, where: g.principal_id == ^principal_id and g.res_id == ^res_id
    )
  end

  def may_read?(%Principal{role: role}, _res_id)
      when role in ["administrator", "member", "system"],
      do: true

  @doc """
  Whether a principal may write to the catalog.
  """
  @spec may_write_catalog?(Principal.t()) :: boolean()
  def may_write_catalog?(%Principal{role: "guest"}), do: false

  def may_write_catalog?(%Principal{role: role})
      when role in ["administrator", "member", "system"],
      do: true
end
