defmodule Pluteus.Corpus.Acquire do
  @moduledoc """
  Fetches a snapshot of a fetched corpus and verifies it before anything reads it
  (spec-05 §5.7), leaving the verified files for the corpus's importer.

  **The snapshot is dated before anything is fetched.** The publisher is asked what it
  announces for every file of the snapshot — a length and a last-modified time — and the
  date is the one those times agree on. Files that disagree are two snapshots, or one being
  regenerated mid-fetch, and nothing is fetched until they agree.

  **Each file is held to what was announced.** Where the registry says a publisher states
  no checksum, the size announced is the only check there is. A file of any other size
  refuses the snapshot, which records a finding and leaves the snapshot in use in use.

  A file already fetched whole is not fetched again, so a snapshot interrupted after its
  largest file resumes at the next one.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Corpus
  alias Pluteus.Corpus.Fetch
  alias Pluteus.Corpus.Repo, as: CorpusRepo
  alias Pluteus.Corpus.Snapshot
  alias Pluteus.Ingest.Finding
  alias Pluteus.Matching.Registry
  alias Pluteus.Repo

  @doc """
  Whether a corpus is due a new snapshot: none has been imported, or the one in use is as
  old as its registry entry allows, and no finding against the corpus is open.

  Answered from what the household holds, so a corpus that is not due costs the publisher
  no request at all.
  """
  @spec due?(String.t(), Date.t()) :: boolean()
  def due?(corpus, today \\ Date.utc_today()) do
    %{every_months: months} = Registry.fetch!(corpus)

    old_enough =
      case Corpus.current(corpus) do
        nil ->
          true

        %Snapshot{stated_on: stated_on} ->
          Date.compare(Date.shift(stated_on, month: months), today) != :gt
      end

    old_enough and not held_back?(corpus)
  end

  # spec-05 §12: due work excludes anything carrying a recorded failure until a person
  # clears it.
  defp held_back?(corpus) do
    Repo.exists?(from f in Finding, where: f.corpus == ^corpus and is_nil(f.cleared_at))
  end

  @typedoc "Each file of a snapshot, and what its publisher announced for it."
  @type announcement :: [{String.t(), Fetch.announced()}]

  @doc """
  Asks the publisher what it announces for every file of a corpus, and begins the
  snapshot those files are dated to.

  Answers the snapshot — new, part fetched, or already verified, imported or refused —
  with the announcement its files are fetched against; files dated differently, or a
  question the publisher did not answer, stop here and nothing is begun.

  Options:

    * `:from` — the address the files are under, where it is not the registry's.
  """
  @spec begin(String.t(), keyword()) ::
          {:ok, Snapshot.t(), announcement()}
          | {:error, {:dates_disagree, %{String.t() => Date.t()}}}
          | {:error, {String.t(), term()}}
  def begin(corpus, options \\ []) do
    %{files: files, verified_by: :size, stated_by: :last_modified} = Registry.fetch!(corpus)

    with {:ok, announced} <- announce(address(corpus, options), files),
         {:ok, stated_on} <- one_date(announced) do
      {:ok, Corpus.begin(corpus, stated_on), announced}
    end
  end

  @doc """
  The files of a snapshot still to fetch: announced, and not yet recorded on it.
  """
  @spec outstanding(Snapshot.t(), announcement()) :: announcement()
  def outstanding(%Snapshot{files: files}, announced),
    do: Enum.reject(announced, fn {file, _said} -> Map.has_key?(files, file) end)

  @doc """
  Fetches one file of a snapshot being fetched, and records it on the snapshot once it is
  whole and the size announced.

  Answers `{:verified, snapshot}` where it was the last file the snapshot lacked,
  `{:fetched, snapshot}` where others remain, `:paused` where the deadline came first
  and what arrived is kept to resume from, the snapshot refused where the file is not the
  size announced, or why the fetch stopped. A snapshot no longer being fetched — refused
  meanwhile, or already verified — is answered as it is, and nothing is fetched.

  Options:

    * `:from` — the address the files are under, where it is not the registry's.
    * `:until` — the deadline `Pluteus.Corpus.Fetch.file/3` stops at.
  """
  @spec fetch_file(Snapshot.t(), String.t(), Fetch.announced(), keyword()) ::
          {:verified | :fetched, Snapshot.t()}
          | :paused
          | {:refused, Snapshot.t()}
          | {:not_fetching, Snapshot.t()}
          | {:error, Fetch.stopped()}
  def fetch_file(%Snapshot{} = snapshot, file, said, options \\ []) do
    snapshot = CorpusRepo.reload!(snapshot)
    directory = Corpus.snapshot_directory(snapshot.corpus, snapshot.stated_on)
    url = address(snapshot.corpus, options) <> file

    case snapshot.state do
      :fetching ->
        case fetched(url, Path.join(directory, file), said.length, options[:until]) do
          :ok ->
            record(snapshot, file, said)

          {:paused, _held} ->
            :paused

          {:disagrees, size} ->
            detail = %{"file" => file, "announced" => said.length, "fetched" => size}
            {:refused, Corpus.refused(snapshot, "size_disagrees", detail)}

          {:error, _stopped} = stopped ->
            stopped
        end

      _not_fetching ->
        {:not_fetching, snapshot}
    end
  end

  @doc """
  Fetches every outstanding file of the snapshot a corpus's publisher announces, one after
  another and with no deadline, and verifies it: `begin/2` and `fetch_file/4` in turn, for
  a fetch that is not run as scheduled jobs.
  """
  @spec fetch(String.t(), keyword()) ::
          {:ok, Snapshot.t()}
          | {:refused, Snapshot.t()}
          | {:error, term()}
  def fetch(corpus, options \\ []) do
    with {:ok, snapshot, announced} <- begin(corpus, options) do
      fetch_all(snapshot, outstanding(snapshot, announced), options)
    end
  end

  defp fetch_all(%Snapshot{state: :refused} = snapshot, _outstanding, _options),
    do: {:refused, snapshot}

  defp fetch_all(%Snapshot{state: :fetching} = snapshot, [], _options),
    do: {:ok, CorpusRepo.reload!(snapshot)}

  defp fetch_all(%Snapshot{state: :fetching} = snapshot, [{file, said} | rest], options) do
    case fetch_file(snapshot, file, said, options) do
      {:fetched, snapshot} -> fetch_all(snapshot, rest, options)
      {:verified, snapshot} -> {:ok, snapshot}
      {:refused, snapshot} -> {:refused, snapshot}
      {:error, stopped} -> {:error, {file, stopped}}
    end
  end

  defp fetch_all(%Snapshot{} = snapshot, _outstanding, _options), do: {:ok, snapshot}

  defp address(corpus, options),
    do: Keyword.get_lazy(options, :from, fn -> Registry.fetch!(corpus).from end)

  defp announce(from, files) do
    Enum.reduce_while(files, {:ok, []}, fn file, {:ok, announced} ->
      case Fetch.head(from <> file, user_agent: Corpus.user_agent()) do
        {:ok, said} -> {:cont, {:ok, [{file, said} | announced]}}
        {:error, stopped} -> {:halt, {:error, {file, stopped}}}
      end
    end)
    |> case do
      {:ok, announced} -> {:ok, Enum.reverse(announced)}
      stopped -> stopped
    end
  end

  defp one_date(announced) do
    dates =
      Map.new(announced, fn {file, said} -> {file, DateTime.to_date(said.last_modified)} end)

    case dates |> Map.values() |> Enum.uniq() do
      [stated_on] -> {:ok, stated_on}
      _several -> {:error, {:dates_disagree, dates}}
    end
  end

  defp fetched(url, destination, length, deadline) do
    case File.stat(destination) do
      {:ok, %File.Stat{size: ^length}} ->
        :ok

      _not_whole ->
        case Fetch.file(url, destination, user_agent: Corpus.user_agent(), until: deadline) do
          {:ok, %{size: ^length}} -> :ok
          {:ok, %{size: size}} -> {:disagrees, size}
          {:paused, _held} = paused -> paused
          {:error, _stopped} = stopped -> stopped
        end
    end
  end

  # The snapshot is read again under a lock, so that two files finishing at once cannot
  # each record itself over the other; the last one the registry names verifies it.
  defp record(snapshot, file, said) do
    {:ok, recorded} =
      CorpusRepo.transaction(fn ->
        held =
          CorpusRepo.one!(from s in Snapshot, where: s.id == ^snapshot.id, lock: "FOR UPDATE")

        files = Map.put(held.files, file, recorded(said))

        if Enum.all?(Registry.fetch!(held.corpus).files, &Map.has_key?(files, &1)) do
          {:verified, Corpus.verified(held, files)}
        else
          {:fetched, Corpus.fetched(held, files)}
        end
      end)

    recorded
  end

  defp recorded(said) do
    %{"size" => said.length, "last_modified" => DateTime.to_iso8601(said.last_modified)}
  end
end
