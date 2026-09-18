defmodule Pluteus.Catalog.Item do
  @moduledoc """
  A physical object exemplifying one manifestation.

  Item is entirely physical. Files are digital items (§5.2), which is a separate
  entity between manifestation and item.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Manifestation

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "items" do
    belongs_to :manifestation, Manifestation, define_field: false
    field :manifestation_id, UUIDv7

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:id, :manifestation_id])
    |> validate_required([:id, :manifestation_id])
    |> foreign_key_constraint(:id)
    |> foreign_key_constraint(:manifestation_id)
  end
end
