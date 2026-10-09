defmodule Pluteus.Catalog.Embodiment do
  @moduledoc """
  LRM-R3, the only many-to-many among the four structural entities.

  One expression may appear in many manifestations, and one manifestation may
  carry many expressions. A second scan of the same original is a new
  manifestation of the existing expression, not a new work.

  ## An augmentation is marked, because the pair is where the difference lives

  §5.3 names three kinds of aggregate, and two of them arrive as the same row. A dub is
  a parallel expression of the film, so its work is the film's; a commentary is an
  expression of a work of its own carried in the film's manifestation (spec-04 §6.5).
  Which one a pairing is is a property of the pairing rather than of either res, so it
  is recorded here: the expression is in that manifestation as an augmentation, not as
  what the manifestation is of.

  A work reached only by augmenting embodiments has no manifestation of its own. It is a
  track of someone else's holding, which is why `Pluteus.Browse.Entries` reads this.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Manifestation

  @primary_key false
  @foreign_key_type UUIDv7
  schema "embodiments" do
    belongs_to :expression, Expression, define_field: false
    belongs_to :manifestation, Manifestation, define_field: false

    field :expression_id, UUIDv7
    field :manifestation_id, UUIDv7
    field :augmentation, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(embodiment, attrs) do
    embodiment
    |> cast(attrs, [:expression_id, :manifestation_id, :augmentation])
    |> validate_required([:expression_id, :manifestation_id, :augmentation])
    |> unique_constraint([:expression_id, :manifestation_id],
      name: :embodiments_expression_id_manifestation_id_index
    )
  end
end
