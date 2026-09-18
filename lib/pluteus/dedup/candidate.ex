defmodule Pluteus.Dedup.Candidate do
  @moduledoc """
  A pair that one signal suggests may be the same thing, and what a person
  decided about it (spec-03 §8.3).

  The pair is stored in one order, so detecting it again meets this row rather
  than creating another, and a decision made here is never reopened by a later
  run.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @signals ~w(digest perceptual external_identifier)a
  @decisions ~w(same_holding distinct)a

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "duplicate_candidates" do
    field :left_id, UUIDv7
    field :right_id, UUIDv7
    field :signal, Ecto.Enum, values: @signals
    field :detected_at, :utc_datetime_usec
    field :decision, Ecto.Enum, values: @decisions
    field :decided_by, UUIDv7
    field :decided_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def decision_changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [:decision, :decided_by, :decided_at])
    |> validate_required([:decision, :decided_by, :decided_at])
    |> check_constraint(:decision, name: :decision_must_be_known)
    |> check_constraint(:decision, name: :decision_is_attributed)
    |> foreign_key_constraint(:decided_by)
  end
end
