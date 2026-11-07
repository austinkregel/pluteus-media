defmodule Pluteus.Workers.Corpora do
  @moduledoc """
  What the jobs keeping a corpus current share: how long they wait between attempts, and
  what the last attempt records when it stops (spec-05 §12).
  """

  alias Pluteus.Ingest

  @doc """
  Ten minutes after the first attempt, then twenty, forty and eighty: long enough for a
  publisher regenerating its files to finish.
  """
  @spec backoff(pos_integer()) :: pos_integer()
  def backoff(attempt), do: 600 * Integer.pow(2, attempt - 1)

  @doc """
  An attempt that stopped: tried again where attempts remain, and recorded as a finding
  against the corpus where this was the last.
  """
  @spec stopped(Oban.Job.t(), String.t(), term()) :: {:error, term()}
  def stopped(%Oban.Job{attempt: last, max_attempts: last}, corpus, stopped) do
    Ingest.record_finding(%{
      stage: :corpus,
      kind: "transient_failure_exhausted",
      permanent: false,
      corpus: corpus,
      detail: %{"attempts" => last, "stopped" => inspect(stopped)}
    })

    {:error, stopped}
  end

  def stopped(_job, _corpus, stopped), do: {:error, stopped}
end
