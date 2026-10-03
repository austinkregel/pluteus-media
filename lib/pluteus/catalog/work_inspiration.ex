defmodule Pluteus.Catalog.WorkInspiration do
  @moduledoc """
  LRM-R21, where one work was the inspiration for another.

  This is how a serial work connects to its issues (§5.4). A series does not contain its
  episodes and an episode is not a part of the series work: each episode is a work of its
  own, and where it sits in the series is an arrangement fact about manifestations. The
  database refuses a whole-part relation between two works standing in this one.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Catalog.Work

  @primary_key false
  @foreign_key_type UUIDv7
  schema "work_inspirations" do
    belongs_to :inspiration, Work, define_field: false
    belongs_to :inspired, Work, define_field: false

    field :inspiration_id, UUIDv7
    field :inspired_id, UUIDv7

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(inspiration, attrs) do
    inspiration
    |> cast(attrs, [:inspiration_id, :inspired_id])
    |> validate_required([:inspiration_id, :inspired_id])
    |> check_constraint(:inspired_id, name: :a_work_is_not_its_own_inspiration)
    |> unique_constraint([:inspiration_id, :inspired_id],
      name: :work_inspirations_inspiration_id_inspired_id_index
    )
  end
end
