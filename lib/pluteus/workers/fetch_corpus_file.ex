defmodule Pluteus.Workers.FetchCorpusFile do
  @moduledoc """
  Fetches one file of a corpus snapshot, for no longer than one job may run (spec-05
  §5.7).

  The fetch stops at its deadline with what has arrived kept, and the job snoozes and
  resumes from there; a snooze consumes no attempt, so a slow publisher is waited out
  rather than counted as failing. Twenty minutes is well inside the lifeline's thirty,
  which would otherwise take a job still downloading for an abandoned one and run it a
  second time beside itself, both writing the one partial file.

  The job that brings in the last file the snapshot lacks verifies it and queues the
  import. A file that is not the size announced refuses the snapshot, and the files still
  queued for it find it refused and fetch nothing.

  A fetch that stops for any other reason is tried again a bounded number of times
  (spec-05 §12), and the last stop is recorded as a finding against the corpus.
  """

  use Oban.Worker,
    queue: :corpora,
    max_attempts: 5,
    unique: [keys: [:snapshot_id, :file], states: :incomplete, period: :infinity]

  alias Pluteus.Corpus.Acquire
  alias Pluteus.Corpus.Repo, as: CorpusRepo
  alias Pluteus.Corpus.Snapshot
  alias Pluteus.Workers.Corpora
  alias Pluteus.Workers.ImportCorpus

  @budget_ms 20 * 60 * 1000

  @doc """
  The job fetching `file` of `snapshot`, carrying what its publisher announced for it.
  """
  @spec new_for(Snapshot.t(), String.t(), Pluteus.Corpus.Fetch.announced()) ::
          Oban.Job.changeset()
  def new_for(%Snapshot{} = snapshot, file, said) do
    new(%{
      corpus: snapshot.corpus,
      snapshot_id: snapshot.id,
      file: file,
      length: said.length,
      last_modified: DateTime.to_iso8601(said.last_modified)
    })
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    snapshot = CorpusRepo.get!(Snapshot, args["snapshot_id"])
    {:ok, last_modified, 0} = DateTime.from_iso8601(args["last_modified"])
    said = %{length: args["length"], last_modified: last_modified}
    deadline = System.monotonic_time(:millisecond) + @budget_ms

    case Acquire.fetch_file(snapshot, args["file"], said, until: deadline) do
      {:fetched, _snapshot} ->
        :ok

      {:verified, verified} ->
        {:ok, _job} = verified |> ImportCorpus.new_for() |> Oban.insert()
        :ok

      :paused ->
        {:snooze, 1}

      {:refused, _snapshot} ->
        :ok

      {:not_fetching, _snapshot} ->
        :ok

      {:error, stopped} ->
        Corpora.stopped(job, args["corpus"], {args["file"], stopped})
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: Corpora.backoff(attempt)
end
