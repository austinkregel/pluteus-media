defmodule Pluteus.Analysis.Source do
  @moduledoc """
  The digital item whose normalized master analysis of a manifestation reads
  (spec-04 §8.1): the earliest placed, until a member names another. Naming a
  different one makes the manifestation due for analysis again, since the
  asset read is part of every derivation's parameters.
  """

  use Ecto.Schema

  @primary_key {:manifestation_id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "analysis_sources" do
    field :digital_item_id, UUIDv7
    field :named_by, UUIDv7

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}
end
