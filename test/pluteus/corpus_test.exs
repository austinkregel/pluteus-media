defmodule Pluteus.CorpusTest do
  @moduledoc """
  Which snapshot of a corpus the household holds (spec-05 §5.6, §5.7, §12).
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Corpus
  alias Pluteus.Ingest

  @corpus "geonames"

  describe "§5.6. A snapshot is of the date its publisher states" do
    test "beginning one twice for one date meets the row the first made" do
      first = Corpus.begin(@corpus, ~D[2026-10-26])
      again = Corpus.begin(@corpus, ~D[2026-10-26])

      assert first.id == again.id
      assert again.state == :fetching
    end

    test "a corpus the registry does not hold cannot be begun" do
      assert_raise Ecto.InvalidChangesetError, fn -> Corpus.begin("myspace", ~D[2026-10-26]) end
    end

    test "its files are kept beneath the corpus and the date" do
      assert Corpus.snapshot_directory(@corpus, ~D[2026-10-26]) ==
               Path.join([Corpus.directory(), @corpus, "2026-10-26"])
    end
  end

  describe "§5.7. The snapshot in use stays in use until its successor is imported" do
    test "lookups read the latest snapshot imported, and nothing short of one" do
      older =
        @corpus |> Corpus.begin(~D[2026-09-01]) |> Corpus.verified(%{}) |> Corpus.imported()

      fetching = Corpus.begin(@corpus, ~D[2026-10-01])

      assert Corpus.current(@corpus).id == older.id

      newer = fetching |> Corpus.verified(%{}) |> Corpus.imported()

      assert Corpus.current(@corpus).id == newer.id
    end

    test "a corpus nothing has been imported for has no current snapshot" do
      Corpus.begin("discogs", ~D[2026-10-01])

      assert Corpus.current("discogs") == nil
    end
  end

  describe "§12. A refused snapshot is a finding a person can see" do
    test "it records why, against the corpus, and leaves the one in use in use" do
      held = @corpus |> Corpus.begin(~D[2026-09-01]) |> Corpus.verified(%{}) |> Corpus.imported()

      refused =
        @corpus
        |> Corpus.begin(~D[2026-10-01])
        |> Corpus.refused("digest_disagrees", %{"file" => "allCountries.zip"})

      assert refused.state == :refused
      assert refused.refused_because == "digest_disagrees"
      assert Corpus.current(@corpus).id == held.id

      assert [finding] = Enum.filter(Ingest.open_findings(), &(&1.corpus == @corpus))
      assert finding.stage == :corpus
      assert finding.kind == "digest_disagrees"
      assert finding.detail == %{"file" => "allCountries.zip", "stated_on" => "2026-10-01"}
    end
  end
end
