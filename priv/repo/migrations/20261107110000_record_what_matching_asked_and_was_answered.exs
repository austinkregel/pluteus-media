defmodule Pluteus.Repo.Migrations.RecordWhatMatchingAskedAndWasAnswered do
  use Ecto.Migration

  # spec-05 §3.3: a match record holds what was asked, what was answered and what was
  # concluded. It is the household's own and is backed up; a corpus's copy is not, and the
  # response here is the only record of what a source said.
  #
  # A record moves through the stages of §7: keyed with what the holding carries, resolved
  # with a source's answer, then applied, raised as a candidate, found empty, or failed.
  def change do
    create table(:match_records, primary_key: false) do
      add :id, :uuid, primary_key: true

      # What the match is about, and — where its key was read from bytes — the asset it
      # was read from (criterion 14).
      add :res_id, references(:res, type: :uuid, on_delete: :nothing), null: false
      add :asset_id, references(:assets, type: :uuid, on_delete: :nothing)

      add :scheme, :text
      add :source_kind, :text, null: false
      add :source, :text, null: false
      add :rank, :text, null: false
      add :rank_order, {:array, :text}, null: false

      add :query, :map, null: false
      add :response, :map
      add :basis, :text
      add :score, :float

      # A corpus's snapshot is the date its publisher states; a provider has none, and
      # its answer is true of the moment it was given (§6.5).
      add :snapshot_on, :date
      add :answered_at, :utc_datetime_usec

      add :conclusion, :map
      add :state, :text, null: false

      # A later answer from the same source about the same res and scheme supersedes this
      # one (§6.5), and this one is kept: the record outlives the match.
      add :superseded_by_id, references(:match_records, type: :uuid, on_delete: :nothing)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:match_records, [:res_id, :scheme, :source],
             where: "superseded_by_id IS NULL",
             name: :one_current_match_per_source
           )

    create index(:match_records, [:state])

    create constraint(:match_records, :match_source_kind_is_known,
             check: "source_kind IN ('holding', 'corpus', 'provider')"
           )

    create constraint(:match_records, :match_state_is_known,
             check: "state IN ('keyed', 'resolved', 'applied', 'candidate', 'empty', 'failed')"
           )

    create constraint(:match_records, :match_basis_is_known,
             check: "basis IS NULL OR basis IN ('equality', 'resemblance')"
           )

    # Everything past keyed holds what the source answered, except a failure, which may
    # have been answered nothing at all.
    create constraint(:match_records, :a_resolved_match_holds_its_answer,
             check: "state IN ('keyed', 'failed') OR (response IS NOT NULL AND basis IS NOT NULL)"
           )

    create constraint(:match_records, :a_corpus_answer_names_its_snapshot,
             check: "source_kind <> 'corpus' OR response IS NULL OR snapshot_on IS NOT NULL"
           )

    create constraint(:match_records, :a_provider_answer_says_when,
             check: "source_kind <> 'provider' OR response IS NULL OR answered_at IS NOT NULL"
           )

    create constraint(:match_records, :a_concluded_match_says_what_it_wrote,
             check: "state NOT IN ('applied', 'candidate') OR conclusion IS NOT NULL"
           )
  end
end
