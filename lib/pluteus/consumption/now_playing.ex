defmodule Pluteus.Consumption.NowPlaying do
  @moduledoc """
  What a principal is playing now on one of its devices. State, not history: it is
  replaced as the client moves on, and is never an event (spec-07 §6.5).
  """

  use Ecto.Schema

  @primary_key false
  schema "now_playing" do
    field :principal_id, UUIDv7, primary_key: true
    field :device_id, UUIDv7, primary_key: true
    field :res_id, UUIDv7
    field :started_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}
end
