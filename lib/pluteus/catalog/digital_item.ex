defmodule Pluteus.Catalog.DigitalItem do
  @moduledoc """
  A file, or package of files, carrying a manifestation's content.

  LRM's `item` is entirely physical, which leaves nothing to hang a downloaded
  file on. §5.2 puts this between manifestation and item instead, and warns
  against the alternative: treating every acquired file as its own singleton
  manifestation, which multiplies the catalogue by the number of copies held.

  It states what the household holds. Whether any bytes still exist is a
  separate question, answered by `Pluteus.Catalog.Asset`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Manifestation

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "digital_items" do
    belongs_to :manifestation, Manifestation, define_field: false
    field :manifestation_id, UUIDv7

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(digital_item, attrs) do
    digital_item
    |> cast(attrs, [:id, :manifestation_id])
    |> validate_required([:id, :manifestation_id])
    |> foreign_key_constraint(:id)
    |> foreign_key_constraint(:manifestation_id)
  end
end
