defmodule Pluteus.Workers.AcquireCorpusTest do
  @moduledoc """
  The daily pass keeping a fetched corpus current asks its publisher nothing on a day the
  corpus is not due, and spreads its retries over hours (spec-05 §5.7, §12).
  """

  use Pluteus.DataCase, async: true
  use Oban.Testing, repo: Pluteus.Jobs.Repo

  alias Pluteus.Corpus
  alias Pluteus.Workers.AcquireCorpus

  test "a corpus whose snapshot is current is left alone, and nothing is fetched" do
    # The registry's address is the publisher's own, so a pass that fetched here would
    # reach it; finishing with no snapshot begun shows it did not.
    held =
      "geonames" |> Corpus.begin(Date.utc_today()) |> Corpus.verified(%{}) |> Corpus.imported()

    assert :ok = perform_job(AcquireCorpus, %{corpus: "geonames"})
    assert Corpus.current("geonames").id == held.id
    assert Pluteus.Corpus.Repo.aggregate(Pluteus.Corpus.Snapshot, :count) == 1
  end

  test "an attempt that stops waits ten minutes, then twice as long each time" do
    assert Enum.map(1..4, &AcquireCorpus.backoff(%Oban.Job{attempt: &1})) ==
             [600, 1200, 2400, 4800]
  end
end
