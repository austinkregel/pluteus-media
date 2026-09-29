defmodule Pluteus.Catalog.Expression do
  @moduledoc """
  A distinct combination of signs realizing one work.

  `work_id` is scalar and not null. LRM-R2 is 1 to M, so an expression realizing
  two works is not a state the schema can represent rather than one it rejects
  after the fact.

  `significant_attributes` holds §6.5's values for this expression, keyed by the
  attribute names its work's type names. The distance between these and the work's
  representative ones is what orders competing expressions (§8.6).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Attributes
  alias Pluteus.Catalog.Work

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "expressions" do
    belongs_to :work, Work, define_field: false
    field :work_id, UUIDv7
    field :significant_attributes, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(expression, attrs) do
    expression
    |> cast(attrs, [:id, :work_id])
    |> validate_required([:id, :work_id])
    |> foreign_key_constraint(:id)
    |> foreign_key_constraint(:work_id)
  end

  @doc """
  The §6.5 attributes this expression carries.

  `permitted` is the attribute set its work's type names, which the caller reads from the
  registry: an attribute outside it is refused here, naming itself, rather than stored and
  then ignored by an ordering that only looks at the type's own.
  """
  @spec attributes_changeset(t(), map(), [String.t()]) :: Ecto.Changeset.t()
  def attributes_changeset(expression, attrs, permitted) do
    expression
    |> cast(attrs, [:significant_attributes])
    |> Attributes.only(:significant_attributes, permitted)
  end
end
