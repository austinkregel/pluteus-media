defmodule Pluteus.Ingest.SerialKey do
  @moduledoc """
  The key a serial was grouped by, and the serial it names (spec-04 §6.9).

  Recorded by ingest, outside the catalog, so that an issue arriving later finds its
  series and a member's renaming of the series changes nothing about which issues join it.
  The key is unique, which is what serializes two placements of one series.

  The work and the manifestation are both named because §5.4 puts the two halves of a
  serial at different levels: the work carries the inspiration relation to each issue's
  work, and the manifestation carries each issue's manifestation as a part.
  """

  use Ecto.Schema

  @primary_key {:key, :string, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "serial_keys" do
    field :serial_work_id, UUIDv7
    field :serial_manifestation_id, UUIDv7

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}
end
