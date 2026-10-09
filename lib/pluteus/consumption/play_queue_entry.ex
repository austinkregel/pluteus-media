defmodule Pluteus.Consumption.PlayQueueEntry do
  @moduledoc """
  One place in a principal's play queue.

  `queued_from` is the grouping the entry came in with, which [spec-10] §12.3 requires be
  recorded rather than inferred: a track reached from its release, from a sequence the
  household composed and on its own are three different answers, and the res alone cannot
  tell them apart. It is nil for an entry queued on its own, which is what there is to
  record about one.
  """

  use Ecto.Schema

  @primary_key false
  schema "play_queue_entries" do
    field :principal_id, UUIDv7, primary_key: true
    field :position, :integer, primary_key: true
    field :res_id, UUIDv7
    field :queued_from, UUIDv7
  end

  @type t :: %__MODULE__{}
end
