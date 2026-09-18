defmodule Pluteus.Workers.PurgeExpired do
  @moduledoc """
  Closes the recycle-bin window (spec-01 §14.1).

  A single attempt. The catalog side of a purge commits before any byte is
  removed, so a retry would find nothing left to purge and succeed, hiding the
  bytes the first attempt could not remove. They are returned as the job's error
  instead, where they stay on the record.
  """

  use Oban.Worker, queue: :lifecycle, max_attempts: 1

  alias Pluteus.Lifecycle

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Enum.flat_map(Lifecycle.purge_expired(), & &1.bytes_not_removed) do
      [] -> :ok
      left -> {:error, {:bytes_not_removed, left}}
    end
  end
end
