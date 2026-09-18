defmodule Pluteus.Workers.AcquireFromInbox do
  @moduledoc """
  One pass of the acquire stage over the configured inbox (spec-04 §4).

  The pass finds its work in the inbox and in recorded state, never in the job,
  so a lost or duplicated job loses and duplicates nothing. One pass runs at a
  time: two concurrent passes would race for the same inbox files.
  """

  use Oban.Worker,
    queue: :ingest,
    max_attempts: 1,
    unique: [states: :incomplete, period: :infinity]

  alias Pluteus.Ingest

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    :pluteus |> Application.fetch_env!(Ingest) |> Keyword.fetch!(:inbox) |> Ingest.acquire()
    :ok
  end
end
