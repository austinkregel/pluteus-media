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
    report = Ingest.acquire(Ingest.inbox())

    acquired = for {_path, {:acquired, outcome}} <- report.files, do: outcome

    if Ingest.crashed?(report.recovered ++ acquired),
      do: {:error, :items_crashed_see_findings},
      else: :ok
  end
end
