defmodule Pluteus.Workers.AcquireCorpus do
  @moduledoc """
  Keeps one fetched corpus current (spec-05 §5.7).

  Scheduled daily and doing nothing on most days: whether the corpus is due is answered
  from the snapshot the household holds, and only a corpus that is due asks its publisher
  anything. One that is due is fetched, verified and imported in turn.

  **A fetch that stops is tried again, a bounded number of times** (spec-05 §12). Its
  partial files are kept, so each attempt resumes, and the attempts are spread over hours
  because the commonest stop — files dated differently while the publisher regenerates
  them — passes on its own. The last attempt's stop is recorded as a finding.

  **An import that raises is recorded as a finding** against the corpus, and the corpus is
  not due again until a person clears it: the verified files are still there to import from.
  """

  use Oban.Worker,
    queue: :corpora,
    max_attempts: 5,
    unique: [states: :incomplete, period: :infinity]

  alias Pluteus.Corpus.Acquire
  alias Pluteus.Corpus.Geonames
  alias Pluteus.Corpus.Snapshot
  alias Pluteus.Ingest

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"corpus" => corpus}} = job) do
    if Acquire.due?(corpus), do: acquire(job, corpus), else: :ok
  end

  # Ten minutes, then twenty, forty and eighty.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: 600 * Integer.pow(2, attempt - 1)

  defp acquire(job, corpus) do
    case Acquire.fetch(corpus) do
      {:ok, %Snapshot{state: :verified} = snapshot} -> import_snapshot(corpus, snapshot)
      {:ok, %Snapshot{state: :imported}} -> :ok
      {:refused, %Snapshot{}} -> :ok
      {:error, stopped} -> stopped(job, corpus, stopped)
    end
  end

  defp import_snapshot(corpus, snapshot) do
    importing = fn -> importer(corpus).import_snapshot(snapshot) end

    case Ingest.isolated(:corpus, %{corpus: corpus}, importing) do
      %Snapshot{state: :imported} -> :ok
      {:crashed, message} -> {:error, message}
    end
  end

  defp stopped(%Oban.Job{attempt: last, max_attempts: last}, corpus, stopped) do
    Ingest.record_finding(%{
      stage: :corpus,
      kind: "transient_failure_exhausted",
      permanent: false,
      corpus: corpus,
      detail: %{"attempts" => last, "stopped" => inspect(stopped)}
    })

    {:error, stopped}
  end

  defp stopped(_job, _corpus, stopped), do: {:error, stopped}

  defp importer("geonames"), do: Geonames
end
