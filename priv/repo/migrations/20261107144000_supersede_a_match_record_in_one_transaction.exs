defmodule Pluteus.Repo.Migrations.SupersedeAMatchRecordInOneTransaction do
  use Ecto.Migration

  # spec-05 §6.5: a later answer from the same source supersedes the earlier one, and only
  # one record per res, scheme and source is current. The earlier record therefore points
  # at its successor before the successor is written — otherwise two would be current at
  # once — and the reference is checked when the transaction commits rather than at once.
  def up do
    execute """
    ALTER TABLE match_records
      ALTER CONSTRAINT match_records_superseded_by_id_fkey DEFERRABLE INITIALLY DEFERRED
    """
  end

  def down do
    execute """
    ALTER TABLE match_records
      ALTER CONSTRAINT match_records_superseded_by_id_fkey NOT DEFERRABLE
    """
  end
end
