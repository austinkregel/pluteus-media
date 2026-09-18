defmodule Pluteus.Catalog.Aggregation do
  @moduledoc """
  LRM-R25, an aggregating expression selecting another expression.

  The aggregating expression realizes a work whose essence is the selection and
  arrangement criteria alone. The aggregated expressions do not become part of
  it, and the works behind them are untouched by the aggregation.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Expression

  @primary_key false
  @foreign_key_type UUIDv7
  schema "aggregations" do
    belongs_to :aggregating_expression, Expression, define_field: false
    belongs_to :aggregated_expression, Expression, define_field: false

    field :aggregating_expression_id, UUIDv7
    field :aggregated_expression_id, UUIDv7
    field :arrangement, :integer

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(aggregation, attrs) do
    aggregation
    |> cast(attrs, [:aggregating_expression_id, :aggregated_expression_id, :arrangement])
    |> validate_required([:aggregating_expression_id, :aggregated_expression_id])
    |> check_constraint(:aggregated_expression_id,
      name: :expression_does_not_aggregate_itself
    )
    |> unique_constraint([:aggregating_expression_id, :aggregated_expression_id],
      name: :aggregations_pair_index
    )
  end
end
