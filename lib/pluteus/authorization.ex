defmodule Pluteus.Authorization do
  @moduledoc """
  What a principal may do beyond being a member (spec-06 §6.1).

  Who may use the deployment at all is the identity provider's decision, made
  before a request arrives. Every member may read and write the catalog, as
  peers: nobody owns a work, and an Administrator holds no more authority over
  what the household holds than a Member does. The Administrator's additional
  powers act on principals and devices.
  """

  alias Pluteus.Principals.Principal

  @administration ~w(
    set_role retire_principal add_identity_to_another revoke_anothers_device
    empty_anothers_deletion
  )a

  @doc """
  Whether a principal holds an administrative power. Only a serving
  Administrator does.
  """
  @spec may?(Principal.t(), atom()) :: boolean()
  def may?(%Principal{role: "administrator", retired_at: nil}, power)
      when power in @administration,
      do: true

  def may?(%Principal{}, power) when power in @administration, do: false
end
