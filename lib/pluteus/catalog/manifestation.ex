defmodule Pluteus.Catalog.Manifestation do
  @moduledoc """
  The set of carriers sharing one content and one production plan.

  A manifestation embodies expressions through `Pluteus.Catalog.Embodiment`
  rather than owning them. That relation is many-to-many, which is what makes an
  aggregate expressible: one container offering several parallel expressions.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "manifestations" do
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(manifestation, attrs) do
    manifestation
    |> cast(attrs, [:id])
    |> validate_required([:id])
    |> foreign_key_constraint(:id)
  end
end
