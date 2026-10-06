defmodule Pluteus.Ingest.TimeSpanKey do
  @moduledoc """
  The date a time-span was grouped by, and the time-span it names.

  A time-span is a res row and its name, with no subtype table of its own, so nothing
  else makes two holdings issued in the same year point at one span. This does: the key
  is the date as the container stated it, and it is unique, which is what serializes two
  placements stating one date.

  Recorded by ingest, outside the catalog, so that a member renaming the span changes
  nothing about which holdings relate to it.
  """

  use Ecto.Schema

  @primary_key {:key, :string, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "time_span_keys" do
    field :time_span_id, UUIDv7

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}
end
