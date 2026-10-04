defmodule Pluteus.Repo.Migrations.HoldAReadingInSeveralParts do
  use Ecto.Migration

  def up do
    # spec-04 §6.9 criterion 38. Several files of one reading are parts of one digital item
    # and carry a part sequence, not tracks of a release: nothing was released as a track,
    # and a reading's file split is not arrangement.
    #
    # The key each reading was grouped by, recorded by ingest outside the catalog as the
    # release, artist and serial keys are. The key is unique, so two files of one reading
    # arriving at once serialize on it and join one digital item. The references are to
    # res, which survives a purge as a tombstone.
    #
    # The manifestation is named beside the digital item because the reading's extent is
    # the whole of it, restated as each part joins, and that extent is the manifestation's.
    create table(:narration_keys, primary_key: false) do
      add :key, :text, primary_key: true
      add :narration_manifestation_id, references(:res, type: :uuid, on_delete: :nothing)
      add :narration_digital_item_id, references(:res, type: :uuid, on_delete: :nothing)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:narration_keys, :a_narration_key_names_both_or_neither,
             check: "num_nulls(narration_manifestation_id, narration_digital_item_id) IN (0, 2)"
           )
  end

  def down do
    drop table(:narration_keys)
  end
end
