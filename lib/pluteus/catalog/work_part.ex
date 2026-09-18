defmodule Pluteus.Catalog.WorkPart do
  @moduledoc """
  LRM-R18, where one work's content is a component of another's.

  This is not how aggregates are expressed. An anthology does not contain the
  works it collects; it selects and arranges their expressions (§5.3). The
  database refuses a whole-part relation between works standing in that
  relationship.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Work

  @primary_key false
  @foreign_key_type UUIDv7
  schema "work_parts" do
    belongs_to :whole, Work, define_field: false
    belongs_to :part, Work, define_field: false

    field :whole_id, UUIDv7
    field :part_id, UUIDv7

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(work_part, attrs) do
    work_part
    |> cast(attrs, [:whole_id, :part_id])
    |> validate_required([:whole_id, :part_id])
    |> check_constraint(:part_id, name: :part_is_not_the_whole)
    |> unique_constraint([:whole_id, :part_id],
      name: :work_parts_whole_id_part_id_index
    )
  end
end
