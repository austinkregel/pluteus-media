defmodule Pluteus.Repo.Migrations.RecordAHoldingThatCarriesNoKey do
  use Ecto.Migration

  # spec-05 §11: an empty result is recorded on the match record, and that is what stops
  # the query running forever. A photograph carrying no position has nothing to ask a
  # gazetteer, and without a record of that its bytes would be read again on every pass.
  # Its record is empty, asked nothing, and holds no answer, because none was sought.
  def up do
    drop constraint(:match_records, :a_resolved_match_holds_its_answer)

    create constraint(:match_records, :a_resolved_match_holds_its_answer,
             check:
               "state IN ('keyed', 'failed') " <>
                 "OR (state = 'empty' AND query = '{}'::jsonb AND response IS NULL) " <>
                 "OR (response IS NOT NULL AND basis IS NOT NULL)"
           )
  end

  def down do
    drop constraint(:match_records, :a_resolved_match_holds_its_answer)

    create constraint(:match_records, :a_resolved_match_holds_its_answer,
             check: "state IN ('keyed', 'failed') OR (response IS NOT NULL AND basis IS NOT NULL)"
           )
  end
end
