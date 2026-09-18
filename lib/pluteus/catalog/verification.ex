defmodule Pluteus.Catalog.Verification do
  @moduledoc """
  One attempt to check that an asset's bytes are still the bytes recorded.

  spec-03 §5.2 requires the outcome of every attempt to be recorded, successful
  or not. A pass that ran and found a mismatch and a pass that never ran are
  different situations, and keeping only successes makes them look alike.

  Recording a mismatch is the whole of what happens. spec-03 §5.4 forbids
  repairing, re-deriving, or silently replacing the asset: detection turns
  silent loss into a known fact, and recovery is a decision made against the
  backup copy with a person in the loop.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Asset

  @outcomes ~w(verified mismatched unreadable)a

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "verifications" do
    belongs_to :asset, Asset, define_field: false
    field :asset_id, UUIDv7

    field :outcome, Ecto.Enum, values: @outcomes
    field :occurred_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @spec outcomes() :: [atom()]
  def outcomes, do: @outcomes

  def changeset(verification, attrs) do
    verification
    |> cast(attrs, [:id, :asset_id, :outcome, :occurred_at])
    |> validate_required([:asset_id, :outcome, :occurred_at])
    |> check_constraint(:outcome, name: :outcome_must_be_known)
    |> foreign_key_constraint(:asset_id)
  end
end
