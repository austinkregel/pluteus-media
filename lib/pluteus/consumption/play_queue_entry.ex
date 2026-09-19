defmodule Pluteus.Consumption.PlayQueueEntry do
  @moduledoc """
  One place in a principal's play queue.
  """

  use Ecto.Schema

  @primary_key false
  schema "play_queue_entries" do
    field :principal_id, UUIDv7, primary_key: true
    field :position, :integer, primary_key: true
    field :res_id, UUIDv7
  end

  @type t :: %__MODULE__{}
end
