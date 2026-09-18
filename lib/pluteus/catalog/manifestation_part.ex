defmodule Pluteus.Catalog.ManifestationPart do
  @moduledoc """
  LRM-R26, where one manifestation is a component of another: a medium of a
  release, a track of a medium, an issue of a serial.

  The position is the arrangement of spec-01 §12.1. Where an aggregate is
  released as a structured manifestation, its order is these positions and not
  anything on the aggregation, so there is one copy of it and it cannot drift.
  No two parts of one whole share a position.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Manifestation

  @primary_key false
  @foreign_key_type UUIDv7
  schema "manifestation_parts" do
    belongs_to :whole, Manifestation, define_field: false
    belongs_to :part, Manifestation, define_field: false

    field :whole_id, UUIDv7
    field :part_id, UUIDv7
    field :position, :integer

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(manifestation_part, attrs) do
    manifestation_part
    |> cast(attrs, [:whole_id, :part_id, :position])
    |> validate_required([:whole_id, :part_id])
    |> check_constraint(:part_id, name: :manifestation_is_not_its_own_part)
    |> check_constraint(:position, name: :position_is_positive)
    |> unique_constraint([:whole_id, :part_id],
      name: :manifestation_parts_whole_id_part_id_index
    )
    |> unique_constraint([:whole_id, :position], name: :one_part_per_position)
    |> foreign_key_constraint(:whole_id)
    |> foreign_key_constraint(:part_id)
  end
end
