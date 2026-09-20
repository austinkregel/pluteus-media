defmodule Pluteus.Ingest.ArtistKey do
  @moduledoc """
  The key an artist was created under, and the artist it names (spec-04 §6.4).

  A credit carrying a MusicBrainz artist identifier is keyed by it, and one
  carrying none by its name in normal form C. Recorded by ingest, outside the
  catalog, so that renaming an artist changes nothing about which credits find
  it. The key is unique, which is what serializes two placements naming one
  artist.
  """

  use Ecto.Schema

  @primary_key {:key, :string, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "artist_keys" do
    field :artist_id, UUIDv7

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}
end
