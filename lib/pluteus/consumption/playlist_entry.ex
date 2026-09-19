defmodule Pluteus.Consumption.PlaylistEntry do
  @moduledoc """
  One place in a playlist. A song may hold several.
  """

  use Ecto.Schema

  @primary_key false
  schema "playlist_entries" do
    belongs_to :playlist, Pluteus.Consumption.Playlist, type: UUIDv7, primary_key: true
    field :position, :integer, primary_key: true
    field :res_id, UUIDv7
  end

  @type t :: %__MODULE__{}
end
