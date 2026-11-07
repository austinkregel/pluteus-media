defmodule Pluteus.Workers.ImportCorpus do
  @moduledoc """
  Imports a verified corpus snapshot, making it the one lookups read (spec-05 §5.7).

  **An import that raises is recorded as a finding** against the corpus, and the corpus is
  not due again until a person clears it: the verified files are still there to import
  from.
  """

  use Oban.Worker,
    queue: :corpora,
    max_attempts: 1,
    unique: [keys: [:snapshot_id], states: :incomplete, period: :infinity]

  alias Pluteus.Corpus.Geonames
  alias Pluteus.Corpus.Repo, as: CorpusRepo
  alias Pluteus.Corpus.Snapshot
  alias Pluteus.Ingest

  @doc """
  The job importing `snapshot`.
  """
  @spec new_for(Snapshot.t()) :: Oban.Job.changeset()
  def new_for(%Snapshot{} = snapshot),
    do: new(%{corpus: snapshot.corpus, snapshot_id: snapshot.id})

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"corpus" => corpus, "snapshot_id" => id}}) do
    case CorpusRepo.get!(Snapshot, id) do
      %Snapshot{state: :verified} = snapshot ->
        importing = fn -> importer(corpus).import_snapshot(snapshot) end

        case Ingest.isolated(:corpus, %{corpus: corpus}, importing) do
          %Snapshot{state: :imported} -> :ok
          {:crashed, message} -> {:error, message}
        end

      %Snapshot{state: :imported} ->
        :ok
    end
  end

  defp importer("geonames"), do: Geonames
end
