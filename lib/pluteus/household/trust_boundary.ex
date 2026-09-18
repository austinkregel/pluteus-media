defmodule Pluteus.Household.TrustBoundary do
  @moduledoc """
  The deployment as a trust boundary: one row, and no name (spec-06 §5.2).

  It also carries the digest of the one-time onboarding secret while the
  deployment has no principals (§6.5).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Res

  @primary_key {:singleton, :boolean, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "trust_boundary" do
    field :collective_agent_id, UUIDv7
    field :collective_agent_kind, Ecto.Enum, values: Res.kinds()
    field :onboarding_secret_digest, :string
    field :onboarding_issued_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(boundary, attrs) do
    boundary
    |> cast(attrs, [
      :collective_agent_id,
      :collective_agent_kind,
      :onboarding_secret_digest,
      :onboarding_issued_at
    ])
    |> put_change(:singleton, true)
    |> check_constraint(:collective_agent_kind, name: :household_is_a_collective_agent)
    |> check_constraint(:collective_agent_id, name: :household_link_is_whole)
    |> foreign_key_constraint(:collective_agent_id,
      name: :trust_boundary_collective_agent_id_fkey
    )
  end
end
