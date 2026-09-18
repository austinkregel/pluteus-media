defmodule Pluteus.Catalog.Category do
  @moduledoc """
  A res's value in one categorization scheme, from one provenance layer
  (spec-01 §4.2.3 by way of LRM, §7.5).

  A category assigned automatically and a member's correction of it are
  separate rows, one per provenance, and the correction wins by the same
  preference that ranks names. Nothing overwrites anything: placement running
  again finds its own row in place and a member's correction beside it.

  Category values are seed data. Nothing here constrains them.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @provenances ~w(seeded automatic local)a

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "categories" do
    field :res_id, UUIDv7
    field :scheme, :string
    field :value, :string
    field :provenance, Ecto.Enum, values: @provenances

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:res_id, :scheme, :value, :provenance])
    |> validate_required([:res_id, :scheme, :value, :provenance])
    |> check_constraint(:provenance, name: :category_provenance_must_be_known)
    |> unique_constraint([:res_id, :scheme, :provenance],
      name: :categories_res_id_scheme_provenance_index
    )
    |> foreign_key_constraint(:res_id)
  end
end
