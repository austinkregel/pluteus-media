defmodule Pluteus.Principals.Identity do
  @moduledoc """
  The `(issuer, subject)` composite an OIDC provider knows a principal by.

  §10.1 forbids keying on `subject` alone, which is unique only within its
  issuer. It also forbids keying anything else on the composite: every reference
  in the system is to the principal's own identifier, which is why an issuer
  changing — a provider migration, a realm rename, a move off a hosted provider
  — is a write to this table and nothing more.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Principals.Principal

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "principal_identities" do
    belongs_to :principal, Principal, define_field: false
    field :principal_id, UUIDv7

    field :issuer, :string
    field :subject, :string

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:id, :principal_id, :issuer, :subject])
    |> validate_required([:principal_id, :issuer, :subject])
    |> unique_constraint([:issuer, :subject])
    |> foreign_key_constraint(:principal_id)
  end
end
