defmodule Pluteus.Catalog.Expression do
  @moduledoc """
  A distinct combination of signs realizing one work.

  `work_id` is scalar and not null. LRM-R2 is 1 to M, so an expression realizing
  two works is not a state the schema can represent rather than one it rejects
  after the fact.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Work

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "expressions" do
    belongs_to :work, Work, define_field: false
    field :work_id, UUIDv7

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(expression, attrs) do
    expression
    |> cast(attrs, [:id, :work_id])
    |> validate_required([:id, :work_id])
    |> foreign_key_constraint(:id)
    |> foreign_key_constraint(:work_id)
  end
end
