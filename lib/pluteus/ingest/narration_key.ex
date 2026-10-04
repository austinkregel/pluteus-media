defmodule Pluteus.Ingest.NarrationKey do
  @moduledoc """
  The key a reading was grouped by, and the reading it names (spec-04 §6.9).

  Recorded by ingest, outside the catalog, so that a later part of a reading joins the
  digital item the first part made and a member's renaming of the book changes nothing
  about which files belong to it. The key is unique, which is what serializes two parts
  arriving at once.

  The manifestation is named beside the digital item because a reading's extent is the
  whole of it, restated as each part joins, and an extent belongs to the manifestation.
  """

  use Ecto.Schema

  @primary_key {:key, :string, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "narration_keys" do
    field :narration_manifestation_id, UUIDv7
    field :narration_digital_item_id, UUIDv7

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}
end
