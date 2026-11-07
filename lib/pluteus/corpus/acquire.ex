defmodule Pluteus.Corpus.Acquire do
  @moduledoc """
  Fetches a snapshot of a fetched corpus and verifies it before anything reads it
  (spec-05 §5.7), leaving the verified files for the corpus's importer.

  **The snapshot is dated before anything is fetched.** The publisher is asked what it
  announces for every file of the snapshot — a length and a last-modified time — and the
  date is the one the registry says states it: the time those files agree on, or the name
  of the directory the publisher's pointer file names. Files whose times disagree are two
  snapshots, or one being regenerated mid-fetch, and nothing is fetched until they agree.

  **Each file is held to what was announced.** Where the publisher publishes checksums,
  they are read before anything is fetched and each file's digest is compared with its
  own. Where the registry says it publishes none, the size announced is the only check
  there is. A file that disagrees refuses the snapshot, which records a finding and leaves
  the snapshot in use in use.

  **Each file's address is fixed when the snapshot begins**, and travels with what was
  announced for it, so a file fetched over several jobs is fetched from one place even
  after the publisher's pointer has moved on to a newer snapshot.

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

  @typedoc """
  What a file of a snapshot is fetched against: where it is, the length and time its
  publisher announced, and the SHA-256 its publisher states where it states one.
  """
  @type said :: %{
          url: String.t(),
          length: non_neg_integer(),
          last_modified: DateTime.t(),
          sha256: String.t() | nil
        }

  @typedoc "Each file of a snapshot, and what its publisher announced for it."
  @type announcement :: [{String.t(), said()}]

  @doc """
  Asks the publisher what it announces for every file of a corpus, and begins the
  snapshot those files are dated to.

  Answers the snapshot — new, part fetched, or already verified, imported or refused —
  with the announcement its files are fetched against. Files dated differently, a pointer
  that names no date, a checksum file that names no line for one of them, or a question
  the publisher did not answer, stop here and nothing is begun.

  Options:

    * `:from` — the address the files, or the publisher's pointer file, are under, where
      it is not the registry's.
  """
  @spec begin(String.t(), keyword()) ::
          {:ok, Snapshot.t(), announcement()}
          | {:error, {:dates_disagree, %{String.t() => Date.t()}}}
          | {:error, {:pointer_names_no_date, String.t()}}
          | {:error, {:no_checksum, String.t()}}
          | {:error, {String.t(), term()}}
  def begin(corpus, options \\ []) do
    %{files: files, verified_by: verified_by, stated_by: stated_by} = Registry.fetch!(corpus)

    with {:ok, under, pointed} <- located(address(corpus, options), stated_by),
         {:ok, digests} <- checksums(under, verified_by, files),
         {:ok, announced} <- announce(under, files, digests),
         {:ok, stated_on} <- dated(stated_by, pointed, announced) do
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
  whole and agrees with what its publisher stated.

  Answers `{:verified, snapshot}` where it was the last file the snapshot lacked,
  `{:fetched, snapshot}` where others remain, `:paused` where the deadline came first
  and what arrived is kept to resume from, the snapshot refused where the file is not the
  size announced or not the digest stated, or why the fetch stopped. A snapshot no longer
  being fetched — refused meanwhile, or already verified — is answered as it is, and
  nothing is fetched.

  Options:

    * `:until` — the deadline `Pluteus.Corpus.Fetch.file/3` stops at.
  """
  @spec fetch_file(Snapshot.t(), String.t(), said(), keyword()) ::
          {:verified | :fetched, Snapshot.t()}
          | :paused
          | {:refused, Snapshot.t()}
          | {:not_fetching, Snapshot.t()}
          | {:error, Fetch.stopped()}
  def fetch_file(%Snapshot{} = snapshot, file, said, options \\ []) do
    snapshot = CorpusRepo.reload!(snapshot)
    directory = Corpus.snapshot_directory(snapshot.corpus, snapshot.stated_on)

    case snapshot.state do
      :fetching ->
        case arrived(said, Path.join(directory, file), options[:until]) do
          {:ok, arrived} -> held_to(snapshot, file, said, arrived)
          {:paused, _held} -> :paused
          {:error, _stopped} = stopped -> stopped
        end

      _not_fetching ->
        {:not_fetching, snapshot}
    end
  end

  defp held_to(snapshot, file, %{length: length} = said, %{size: size} = arrived) do
    cond do
      size != length ->
        detail = %{"file" => file, "announced" => length, "fetched" => size}
        {:refused, Corpus.refused(snapshot, "size_disagrees", detail)}

      said.sha256 && said.sha256 != arrived.digests.sha256 ->
        detail = %{"file" => file, "stated" => said.sha256, "fetched" => arrived.digests.sha256}
        {:refused, Corpus.refused(snapshot, "digest_disagrees", detail)}

      true ->
        record(snapshot, file, said)
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

  # Where the snapshot's files are: under the address itself, or under the directory the
  # publisher's pointer file names there, along with the date that name states. A name
  # stating none is no snapshot, and nothing under it is asked for.
  defp located(from, :last_modified), do: {:ok, from, nil}

  defp located(from, {:pointer, pointer}) do
    case Fetch.text(from <> pointer, user_agent: Corpus.user_agent()) do
      {:ok, body} ->
        directory = String.trim(body)

        with {:ok, stated_on} <- named_date(directory) do
          {:ok, from <> directory <> "/", stated_on}
        end

      {:error, stopped} ->
        {:error, {pointer, stopped}}
    end
  end

  # A directory named for the time the export began, `YYYYMMDD-HHMMSS`.
  defp named_date(directory) do
    with <<year::binary-4, month::binary-2, day::binary-2, "-", _time::binary-6>> <- directory,
         {:ok, stated_on} <- Date.from_iso8601("#{year}-#{month}-#{day}") do
      {:ok, stated_on}
    else
      _no_date -> {:error, {:pointer_names_no_date, directory}}
    end
  end

  # The digest the publisher states for each file, read from its checksum file, one
  # `<digest> *<file>` or `<digest>  <file>` line per file.
  defp checksums(_under, :size, _files), do: {:ok, %{}}

  defp checksums(under, {:sha256, checksums}, files) do
    with {:ok, body} <- checksum_file(under <> checksums, checksums) do
      stated =
        body
        |> String.split("\n", trim: true)
        |> Map.new(fn line ->
          [digest, named] = String.split(line, ~r/\s+/, parts: 2)
          {String.trim_leading(named, "*"), String.downcase(digest)}
        end)

      case Enum.reject(files, &Map.has_key?(stated, &1)) do
        [] -> {:ok, Map.take(stated, files)}
        [unstated | _rest] -> {:error, {:no_checksum, unstated}}
      end
    end
  end

  defp checksum_file(url, name) do
    case Fetch.text(url, user_agent: Corpus.user_agent()) do
      {:ok, body} -> {:ok, body}
      {:error, stopped} -> {:error, {name, stopped}}
    end
  end

  defp announce(under, files, digests) do
    Enum.reduce_while(files, {:ok, []}, fn file, {:ok, announced} ->
      url = under <> file

      case Fetch.head(url, user_agent: Corpus.user_agent()) do
        {:ok, said} ->
          said = Map.merge(said, %{url: url, sha256: Map.get(digests, file)})
          {:cont, {:ok, [{file, said} | announced]}}

        {:error, stopped} ->
          {:halt, {:error, {file, stopped}}}
      end
    end)
    |> case do
      {:ok, announced} -> {:ok, Enum.reverse(announced)}
      stopped -> stopped
    end
  end

  defp dated(:last_modified, nil, announced) do
    dates =
      Map.new(announced, fn {file, said} -> {file, DateTime.to_date(said.last_modified)} end)

    case dates |> Map.values() |> Enum.uniq() do
      [stated_on] -> {:ok, stated_on}
      _several -> {:error, {:dates_disagree, dates}}
    end
  end

  defp dated({:pointer, _pointer}, %Date{} = stated_on, _announced), do: {:ok, stated_on}

  # What is held of a file: one already whole at its destination is what arrived, and is
  # digested where the publisher states a digest; otherwise it is fetched, resuming any
  # partial download.
  defp arrived(said, destination, deadline) do
    algorithms = if said.sha256, do: [:sha256], else: []

    case File.stat(destination) do
      {:ok, %File.Stat{size: size}} ->
        {:ok, %{size: size, digests: Map.new(algorithms, &{&1, Fetch.digest(destination, &1)})}}

      {:error, :enoent} ->
        Fetch.file(said.url, destination,
          user_agent: Corpus.user_agent(),
          until: deadline,
          digests: algorithms
        )
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
    %{
      "url" => said.url,
      "size" => said.length,
      "last_modified" => DateTime.to_iso8601(said.last_modified),
      "sha256" => said.sha256
    }
  end
end
