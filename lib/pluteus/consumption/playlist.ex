defmodule Pluteus.Consumption.Playlist do
  @moduledoc """
  A principal's ordered list of songs (spec-07 §6.6). Consumption data, not
  catalog content: it says what one person chose to hear.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Pluteus.Consumption.PlaylistEntry

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "playlists" do
    field :principal_id, UUIDv7
    field :name, :string
    field :comment, :string

    has_many :entries, PlaylistEntry, preload_order: [asc: :position]

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(playlist, attrs) do
    playlist
    |> cast(attrs, [:principal_id, :name, :comment])
    |> validate_required([:principal_id, :name])
  end
end
