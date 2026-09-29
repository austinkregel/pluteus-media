defmodule Pluteus.Catalog.ExpressionChoice do
  @moduledoc """
  The expression a principal chose for a work, where nothing else could choose for them
  ([spec-10] §8.1).

  §8.1 forbids guessing: where a work's significant attributes do not separate its
  expressions and §8.6's preferences do not either, the surface asks once and records the
  answer. This is where the answer goes.

  One row per principal per work, so answering again replaces the answer rather than adding
  to it. The choice is that principal's: [spec-10] §14.5's confidentiality reaches it, and
  as with the preferences that is a property of this module's shape — no function here
  answers one principal's choice to another.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Work
  alias Pluteus.Principals.Principal

  @primary_key false
  @foreign_key_type UUIDv7
  schema "principal_expression_choices" do
    belongs_to :principal, Principal, primary_key: true, type: UUIDv7
    belongs_to :work, Work, primary_key: true, type: UUIDv7
    belongs_to :expression, Expression, define_field: false

    field :expression_id, UUIDv7

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(choice, attrs) do
    choice
    |> cast(attrs, [:principal_id, :work_id, :expression_id])
    |> validate_required([:principal_id, :work_id, :expression_id])
    |> unique_constraint([:principal_id, :work_id],
      name: :principal_expression_choices_pkey
    )
    |> foreign_key_constraint(:principal_id)
    |> foreign_key_constraint(:work_id)
    |> foreign_key_constraint(:expression_id)
  end
end
