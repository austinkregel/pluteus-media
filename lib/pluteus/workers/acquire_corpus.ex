defmodule Pluteus.Workers.AcquireCorpus do
  @moduledoc """
  Keeps one fetched corpus current (spec-05 §5.7): the daily pass that begins a snapshot
  and hands its files out to be fetched.

  Doing nothing on most days: whether the corpus is due is answered from the snapshot the
  household holds, and only a corpus that is due asks its publisher anything. One that is
  due has its snapshot dated and begun, and every file it still lacks is queued as a
  `Pluteus.Workers.FetchCorpusFile` of its own; a snapshot already verified is queued for
  `Pluteus.Workers.ImportCorpus`.

  A file can take longer to arrive than any one job may run — allCountries has taken over
  half an hour, past the lifeline that rescues a job running too long — so no job here
  fetches anything, and each that does stops within its own time and resumes.

  **Asking the publisher is tried again, a bounded number of times** (spec-05 §12),
  spread over hours because the commonest stop — files dated differently while the
  publisher regenerates them — passes on its own. The last attempt's stop is recorded as a
  finding against the corpus.
  """

  use Oban.Worker,
    queue: :corpora,
    max_attempts: 5,
    unique: [states: :incomplete, period: :infinity]

  alias Pluteus.Corpus.Acquire
  alias Pluteus.Corpus.Snapshot
  alias Pluteus.Workers.Corpora
  alias Pluteus.Workers.FetchCorpusFile
  alias Pluteus.Workers.ImportCorpus

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"corpus" => corpus}} = job) do
    if Acquire.due?(corpus), do: begin(job, corpus), else: :ok
  end

  # Ten minutes, then twenty, forty and eighty.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: Corpora.backoff(attempt)

  defp begin(job, corpus) do
    case Acquire.begin(corpus) do
      {:ok, %Snapshot{state: :fetching} = snapshot, announced} ->
        for {file, said} <- Acquire.outstanding(snapshot, announced) do
          {:ok, _job} = snapshot |> FetchCorpusFile.new_for(file, said) |> Oban.insert()
        end

        :ok

      {:ok, %Snapshot{state: :verified} = snapshot, _announced} ->
        {:ok, _job} = snapshot |> ImportCorpus.new_for() |> Oban.insert()
        :ok

      {:ok, %Snapshot{state: state}, _announced} when state in [:imported, :refused] ->
        :ok

      {:error, stopped} ->
        Corpora.stopped(job, corpus, stopped)
    end
  end
end
