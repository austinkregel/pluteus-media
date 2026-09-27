defmodule Pluteus.Authorization do
  @moduledoc """
  What a principal may do beyond being a member (spec-06 §6.1), and what a
  credential on a device may do within that (§4.2).

  Who may use the deployment at all is the identity provider's decision, made
  before a request arrives. Every member may read and write the catalog, as
  peers: nobody owns a work, and an Administrator holds no more authority over
  what the household holds than a Member does. The Administrator's additional
  powers act on principals and devices.

  Two questions, deliberately over two subjects. `may?/2` asks what a *principal*
  may do and takes one. `granted?/2` asks what a *credential* may do and takes no
  principal at all — which is how §4.2's "MUST NOT be widened by the principal's
  role changing afterwards" is structural: there is no code path by which a current
  role could reach the answer.
  """

  alias Pluteus.Principals.DeviceCredential
  alias Pluteus.Principals.Principal

  @administration ~w(
    set_role retire_principal add_identity_to_another revoke_anothers_device
    empty_anothers_deletion
  )a

  # The vocabulary belongs to the column it constrains, so it is read from there
  # rather than restated: one list, and the database's `grant_is_grantable` check
  # says the same thing in SQL.
  @grants DeviceCredential.grantable()

  # §4.2: "A narrowed credential MUST NOT grant any operation in §6.1's
  # Administrator row, and MUST NOT grant identity mapping (§3.3), whatever its
  # principal's role", and spec-10 §18.3 adds the catalog writes of §15. None of
  # them is in `@grants`, so a credential cannot record one; these clauses are what
  # make the refusal the credential's own answer rather than a consequence of
  # routing.
  @denied ~w(add_identity_to_self write_catalog)a

  @doc """
  Whether a principal holds an administrative power. Only a serving
  Administrator does.
  """
  @spec may?(Principal.t(), atom()) :: boolean()
  def may?(%Principal{role: "administrator", retired_at: nil}, power)
      when power in @administration,
      do: true

  def may?(%Principal{}, power) when power in @administration, do: false

  @doc """
  Every operation in §6.1's Administrator row.
  """
  @spec administration() :: [atom()]
  def administration, do: @administration

  @doc """
  Every operation a credential's grant may name.
  """
  @spec grantable() :: [atom()]
  def grantable, do: @grants

  @doc """
  Whether a credential's recorded grant covers an operation.

  Takes no principal, which is the point: a role cannot reach this answer, so a
  grant cannot widen when a role changes (§4.2).

  The administrative and identity-mapping operations answer `false` outright,
  because no grant may name one. An operation outside both sets raises: a caller
  asking whether a credential grants something nobody has classified has found a
  gap in the classification, and answering `false` would hide it while answering
  `true` would open it.
  """
  @spec granted?(DeviceCredential.t(), atom()) :: boolean()
  def granted?(%DeviceCredential{granted: granted}, operation) when operation in @grants,
    do: operation in granted

  def granted?(%DeviceCredential{}, operation)
      when operation in @administration or operation in @denied,
      do: false

  @doc """
  Every operation a principal's role may grant a credential on its device.

  There is no clause for the System principal: spec-06 §6.1 puts it outside §3's
  authentication path, so it has no device to enrol and asking raises.
  """
  @spec grantable_to(Principal.t()) :: [atom()]
  def grantable_to(%Principal{role: role}) when role in ["administrator", "member"], do: @grants
end
