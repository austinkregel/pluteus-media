defmodule Pluteus.Lifecycle.Tombstone do
  @moduledoc """
  The record that a res existed and was purged.

  §14.3 requires the identifier, the entity class and the time of purge to be
  kept indefinitely. The res row is kept alongside it, so the identifier stays
  taken by primary key: §4.1's prohibition on reuse is then a property of the
  table rather than a check a writer could skip.
  """

  use Ecto.Schema

  alias Pluteus.Catalog.Res

  @primary_key {:res_id, UUIDv7, autogenerate: false}
  schema "tombstones" do
    field :kind, Ecto.Enum, values: Res.kinds()
    field :purged_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}
end
