defmodule Pluteus.Ingest.ReleaseKey do
  @moduledoc """
  The key a release was grouped by, and the release it names (spec-04 §6.4).

  Recorded by ingest, outside the catalog, so that a track arriving later finds
  its release and a member's renaming of the release changes nothing about
  which tracks join it. The key is unique, which is what serializes two
  placements of one release.
  """

  use Ecto.Schema

  @primary_key {:key, :string, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "release_keys" do
    field :release_manifestation_id, UUIDv7
    field :release_expression_id, UUIDv7

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}
end
