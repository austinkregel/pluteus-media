defmodule Pluteus.Ingest.MusicBrainzArtist do
  @moduledoc """
  What MusicBrainz said about one artist identifier, and the agent created for
  it (spec-04 §6.4). One row per identifier, so one agent however many credits
  carry it.
  """

  use Ecto.Schema

  @primary_key {:musicbrainz_id, Ecto.UUID, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "musicbrainz_artists" do
    field :type, :string
    field :agent_id, UUIDv7
    field :attempts, :integer, default: 0
    field :looked_up_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}
end
