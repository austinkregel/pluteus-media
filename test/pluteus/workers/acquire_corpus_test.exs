defmodule Pluteus.Workers.AcquireCorpusTest do
  @moduledoc """
  The jobs keeping a fetched corpus current: the daily pass asks its publisher nothing on
  a day the corpus is not due, a file's job leaves a snapshot no longer being fetched
  alone, an import runs only on a verified snapshot, and retries are spread over hours
  (spec-05 §5.7, §12).
  """

  use Pluteus.DataCase, async: true
  use Oban.Testing, repo: Pluteus.Jobs.Repo

  alias Pluteus.Corpus
  alias Pluteus.Workers.AcquireCorpus
  alias Pluteus.Workers.FetchCorpusFile
  alias Pluteus.Workers.ImportCorpus

  @said %{
    url: "http://127.0.0.1:9/allCountries.zip",
    length: 10,
    last_modified: ~U[2026-11-06 02:50:44Z],
    sha256: nil
  }

  test "a corpus whose snapshot is current is left alone, and nothing is fetched" do
    # The registry's address is the publisher's own, so a pass that fetched here would
    # reach it; finishing with no snapshot begun shows it did not.
    held =
      "geonames" |> Corpus.begin(Date.utc_today()) |> Corpus.verified(%{}) |> Corpus.imported()

    assert :ok = perform_job(AcquireCorpus, %{corpus: "geonames"})
    assert Corpus.current("geonames").id == held.id
    assert Pluteus.Corpus.Repo.aggregate(Pluteus.Corpus.Snapshot, :count) == 1
  end

  test "a file's job for a snapshot refused meanwhile fetches nothing and finishes" do
    refused =
      "geonames" |> Corpus.begin(~D[2026-11-06]) |> Corpus.refused("size_disagrees", %{})

    args =
      refused
      |> FetchCorpusFile.new_for("allCountries.zip", @said)
      |> Map.fetch!(:changes)
      |> Map.fetch!(:args)

    assert :ok = perform_job(FetchCorpusFile, args)
  end

  test "an import of a snapshot already imported does nothing" do
    imported =
      "geonames" |> Corpus.begin(~D[2026-11-06]) |> Corpus.verified(%{}) |> Corpus.imported()

    assert :ok = perform_job(ImportCorpus, %{corpus: "geonames", snapshot_id: imported.id})
  end

  test "an attempt that stops waits ten minutes, then twice as long each time" do
    for worker <- [AcquireCorpus, FetchCorpusFile] do
      assert Enum.map(1..4, &worker.backoff(%Oban.Job{attempt: &1})) == [600, 1200, 2400, 4800]
    end
  end
end
