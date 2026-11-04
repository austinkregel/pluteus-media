defmodule Pluteus.Repo.Migrations.RecordAFindingAgainstACorpus do
  use Ecto.Migration

  # spec-05 §12: a stage that cannot complete records why as a finding a person can see. A
  # corpus that will not fetch or whose file does not verify has no acquisition, holding or
  # input to be recorded against; the corpus itself is the subject, named as the registry
  # names it.
  @stages ~w(acquire examine identify place normalize analyse purge credit)

  def up do
    alter table(:ingest_findings) do
      add :corpus, :text
    end

    replace_stages(@stages ++ ["corpus"])

    drop constraint(:ingest_findings, :a_finding_has_a_subject)

    create constraint(:ingest_findings, :a_finding_has_a_subject,
             check:
               "num_nonnulls(acquisition_id, location, digital_item_id, input_id, " <>
                 "musicbrainz_id, corpus) >= 1"
           )

    # One open at a time per corpus, as per location and per MusicBrainz identifier: a
    # corpus carrying one is out of due work until it is cleared, so a second means that
    # exclusion failed.
    create unique_index(:ingest_findings, [:corpus],
             where: "corpus IS NOT NULL AND cleared_at IS NULL",
             name: :ingest_findings_one_open_per_corpus_index
           )
  end

  def down do
    drop index(:ingest_findings, [:corpus], name: :ingest_findings_one_open_per_corpus_index)

    drop constraint(:ingest_findings, :a_finding_has_a_subject)

    create constraint(:ingest_findings, :a_finding_has_a_subject,
             check:
               "num_nonnulls(acquisition_id, location, digital_item_id, input_id, musicbrainz_id) >= 1"
           )

    replace_stages(@stages)

    alter table(:ingest_findings) do
      remove :corpus
    end
  end

  defp replace_stages(stages) do
    drop constraint(:ingest_findings, :stage_must_be_known)

    create constraint(:ingest_findings, :stage_must_be_known,
             check: "stage IN (#{Enum.map_join(stages, ", ", &"'#{&1}'")})"
           )
  end
end
