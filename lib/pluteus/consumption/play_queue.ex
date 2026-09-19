defmodule Pluteus.Consumption.PlayQueue do
  @moduledoc """
  A principal's play queue: its songs in order, which of them is current, how
  far into it, and which of the principal's devices saved it last.
  """

  use Ecto.Schema

  alias Pluteus.Consumption.PlayQueueEntry

  @primary_key {:principal_id, UUIDv7, autogenerate: false}
  schema "play_queues" do
    field :current_index, :integer
    field :position_ms, :integer
    field :changed_by_device_id, UUIDv7

    has_many :entries, PlayQueueEntry,
      foreign_key: :principal_id,
      references: :principal_id,
      preload_order: [asc: :position]

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}
end
