defmodule Pluteus.Corpus do
  @moduledoc """
  The corpora the household holds a copy of, and which snapshot of each (spec-05 §5.5,
  §5.6, §5.7).

  A snapshot is begun when its files start arriving, verified once every file agrees with
  what its publisher stated, and imported once its data is what lookups read. The snapshot
  in use is the latest one imported, so a fetch that fails or a file that does not verify
  leaves the household with the corpus it already had rather than with none.

  A refusal is a finding as well as a state. spec-05 §12 requires a stage that cannot
  complete to record why where a person can see it, and the snapshot row is in a database
  no surface reads.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Corpus.Repo
  alias Pluteus.Corpus.Snapshot
  alias Pluteus.Ingest

  @doc """
  Where corpora are fetched to and dropped into.
  """
  @spec directory() :: Path.t()
  def directory, do: :pluteus |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(:directory)

  @doc """
  Where one snapshot's files are kept until it is imported.
  """
  @spec snapshot_directory(String.t(), Date.t()) :: Path.t()
  def snapshot_directory(corpus, %Date{} = stated_on) do
    Path.join([directory(), corpus, Date.to_iso8601(stated_on)])
  end

  @doc """
  The snapshot of a corpus begun for the date its publisher states, made where none is.

  A fetch that runs twice for one date meets the row the first one made, so an
  interrupted fetch resumes against the same snapshot rather than beginning another.
  """
  @spec begin(String.t(), Date.t()) :: Snapshot.t()
  def begin(corpus, %Date{} = stated_on) do
    %{corpus: corpus, stated_on: stated_on}
    |> Snapshot.begun_changeset()
    |> Repo.insert!(on_conflict: :nothing, conflict_target: [:corpus, :stated_on])

    Repo.get_by!(Snapshot, corpus: corpus, stated_on: stated_on)
  end

  @doc """
  Records that every file of a snapshot agreed with what its publisher stated.
  """
  @spec verified(Snapshot.t(), map()) :: Snapshot.t()
  def verified(%Snapshot{state: :fetching} = snapshot, files) do
    snapshot |> Snapshot.verified_changeset(files) |> Repo.update!()
  end

  @doc """
  Records that a snapshot's data is now what lookups read.
  """
  @spec imported(Snapshot.t(), DateTime.t()) :: Snapshot.t()
  def imported(%Snapshot{state: :verified} = snapshot, now \\ DateTime.utc_now()) do
    snapshot |> Snapshot.imported_changeset(now) |> Repo.update!()
  end

  @doc """
  Refuses a snapshot and records why as a finding against the corpus, which keeps the
  corpus out of due work until a person clears it.
  """
  @spec refused(Snapshot.t(), String.t(), map()) :: Snapshot.t()
  def refused(%Snapshot{} = snapshot, kind, detail) do
    refused = snapshot |> Snapshot.refused_changeset(kind) |> Repo.update!()

    Ingest.record_finding(%{
      stage: :corpus,
      kind: kind,
      permanent: true,
      corpus: snapshot.corpus,
      detail: Map.put(detail, "stated_on", Date.to_iso8601(snapshot.stated_on)),
      recorded_at: DateTime.utc_now()
    })

    refused
  end

  @doc """
  The snapshot lookups read for a corpus: the latest imported, or nil where none has been.
  """
  @spec current(String.t()) :: Snapshot.t() | nil
  def current(corpus) do
    Repo.one(
      from s in Snapshot,
        where: s.corpus == ^corpus and s.state == :imported,
        order_by: [desc: s.stated_on],
        limit: 1
    )
  end
end
