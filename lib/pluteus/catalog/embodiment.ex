defmodule Pluteus.Catalog.Embodiment do
  @moduledoc """
  LRM-R3, the only many-to-many among the four structural entities.

  One expression may appear in many manifestations, and one manifestation may
  carry many expressions. A second scan of the same original is a new
  manifestation of the existing expression, not a new work.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Manifestation

  @primary_key false
  @foreign_key_type UUIDv7
  schema "embodiments" do
    belongs_to :expression, Expression, define_field: false
    belongs_to :manifestation, Manifestation, define_field: false

    field :expression_id, UUIDv7
    field :manifestation_id, UUIDv7

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(embodiment, attrs) do
    embodiment
    |> cast(attrs, [:expression_id, :manifestation_id])
    |> validate_required([:expression_id, :manifestation_id])
    |> unique_constraint([:expression_id, :manifestation_id],
      name: :embodiments_expression_id_manifestation_id_index
    )
  end
end
