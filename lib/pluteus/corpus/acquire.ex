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

  @doc """
  Fetches the snapshot a corpus's publisher currently announces, and verifies it.

  Returns the snapshot verified, or already imported where the household holds it; the
  snapshot refused where a file did not verify; or why the fetch stopped, where it can be
  tried again and what arrived is kept to resume from.

  Options:

    * `:from` — the address the files are under, where it is not the registry's.
  """
  @spec fetch(String.t(), keyword()) ::
          {:ok, Snapshot.t()}
          | {:refused, Snapshot.t()}
          | {:error, {:dates_disagree, %{String.t() => Date.t()}}}
          | {:error, {String.t(), Fetch.stopped() | term()}}
  def fetch(corpus, options \\ []) do
    %{files: files, verified_by: :size, stated_by: :last_modified} =
      entry = Registry.fetch!(corpus)

    from = Keyword.get(options, :from, entry.from)

    with {:ok, announced} <- announce(from, files),
         {:ok, stated_on} <- one_date(announced) do
      corpus |> Corpus.begin(stated_on) |> continue(from, announced)
    end
  end

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

  defp continue(%Snapshot{state: :fetching} = snapshot, from, announced) do
    directory = Corpus.snapshot_directory(snapshot.corpus, snapshot.stated_on)

    announced
    |> Enum.reduce_while({:ok, %{}}, fn {file, said}, {:ok, files} ->
      case fetch_file(from <> file, Path.join(directory, file), said.length) do
        :ok ->
          {:cont, {:ok, Map.put(files, file, recorded(said))}}

        {:disagrees, size} ->
          {:halt, {:disagrees, %{"file" => file, "announced" => said.length, "fetched" => size}}}

        {:error, stopped} ->
          {:halt, {:error, {file, stopped}}}
      end
    end)
    |> case do
      {:ok, files} -> {:ok, Corpus.verified(snapshot, files)}
      {:disagrees, detail} -> {:refused, Corpus.refused(snapshot, "size_disagrees", detail)}
      {:error, _stopped} = stopped -> stopped
    end
  end

  defp continue(%Snapshot{state: state} = snapshot, _from, _announced)
       when state in [:verified, :imported],
       do: {:ok, snapshot}

  defp continue(%Snapshot{state: :refused} = snapshot, _from, _announced),
    do: {:refused, snapshot}

  defp fetch_file(url, destination, length) do
    case File.stat(destination) do
      {:ok, %File.Stat{size: ^length}} ->
        :ok

      _not_whole ->
        case Fetch.file(url, destination, user_agent: Corpus.user_agent()) do
          {:ok, %{size: ^length}} -> :ok
          {:ok, %{size: size}} -> {:disagrees, size}
          {:error, _stopped} = stopped -> stopped
        end
    end
  end

  defp recorded(said) do
    %{"size" => said.length, "last_modified" => DateTime.to_iso8601(said.last_modified)}
  end
end
