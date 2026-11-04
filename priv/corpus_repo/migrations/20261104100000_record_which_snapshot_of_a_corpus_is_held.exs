defmodule Pluteus.Corpus.Repo.Migrations.RecordWhichSnapshotOfACorpusIsHeld do
  use Ecto.Migration

  # spec-05 §5.6: every corpus records the date of the data it holds, and every match drawn
  # from one records that snapshot. §5.7: a fetched snapshot is verified before anything
  # reads it, and the one in use stays in use until its successor is verified and imported,
  # so a snapshot moves through states rather than appearing whole.
  def change do
    create table(:corpus_snapshots) do
      add :corpus, :text, null: false
      add :stated_on, :date, null: false
      add :state, :text, null: false
      add :files, :map, null: false, default: %{}
      add :refused_because, :text
      add :imported_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    # One snapshot of one corpus per date the publisher states, so a fetch that runs twice
    # meets the row the first one made.
    create unique_index(:corpus_snapshots, [:corpus, :stated_on])

    create constraint(:corpus_snapshots, :snapshot_state_is_known,
             check: "state IN ('fetching', 'verified', 'imported', 'refused')"
           )

    # A refusal says why, and only a refusal does; an import says when.
    create constraint(:corpus_snapshots, :a_refusal_says_why,
             check: "(state = 'refused') = (refused_because IS NOT NULL)"
           )

    create constraint(:corpus_snapshots, :an_import_says_when,
             check: "(state = 'imported') = (imported_at IS NOT NULL)"
           )
  end
end
