defmodule Pluteus.Repo.Migrations.PositionAnIssueWithinItsSerial do
  use Ecto.Migration

  def up do
    # LRM-R21, inspiration. spec-01 §5.4 makes this the relation between a serial work and
    # its issues, and spec-04 §6.9 criterion 39 reaches it for a comic series and a
    # podcast. It is not whole-part: a series does not contain its episodes, and §5.4
    # forbids saying that it does.
    create table(:work_inspirations, primary_key: false) do
      add :inspiration_id, references(:works, type: :uuid, on_delete: :nothing), null: false
      add :inspired_id, references(:works, type: :uuid, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:work_inspirations, [:inspiration_id, :inspired_id])
    create index(:work_inspirations, [:inspired_id])

    create constraint(:work_inspirations, :a_work_is_not_its_own_inspiration,
             check: "inspiration_id <> inspired_id"
           )

    execute """
    CREATE TRIGGER record_catalog_write
      AFTER INSERT OR UPDATE OR DELETE ON work_inspirations
      FOR EACH ROW EXECUTE FUNCTION
        record_catalog_write('{inspiration_id,inspired_id}', '{inspiration_id,inspired_id}');
    """

    # §5.4's prohibition, enforced the way §5.3's already is between whole-part and
    # aggregation: from both sides, because either relation may be written first. A pair
    # standing in inspiration is a pair whose structure lives at manifestation level, so a
    # whole-part relation between them is the confusion §5.4 exists to refuse.
    execute """
    CREATE FUNCTION reject_inspiring_whole_part() RETURNS trigger AS $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM work_inspirations
        WHERE inspiration_id = NEW.whole_id AND inspired_id = NEW.part_id
      ) THEN
        RAISE EXCEPTION
          'work % is an inspiration for work %; their structure is at manifestation level',
          NEW.whole_id, NEW.part_id
          USING ERRCODE = '23514';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER work_part_is_not_inspiration
      BEFORE INSERT OR UPDATE ON work_parts
      FOR EACH ROW EXECUTE FUNCTION reject_inspiring_whole_part();
    """

    execute """
    CREATE FUNCTION reject_whole_part_inspiration() RETURNS trigger AS $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM work_parts
        WHERE whole_id = NEW.inspiration_id AND part_id = NEW.inspired_id
      ) THEN
        RAISE EXCEPTION
          'work % already has work % as a part; it cannot also be its inspiration',
          NEW.inspiration_id, NEW.inspired_id
          USING ERRCODE = '23514';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER inspiration_is_not_work_part
      BEFORE INSERT OR UPDATE ON work_inspirations
      FOR EACH ROW EXECUTE FUNCTION reject_whole_part_inspiration();
    """

    # The key each serial was grouped by, recorded by ingest outside the catalog as
    # `release_keys` and `artist_keys` are. The key is unique, so two issues of one series
    # arriving at once serialize on it and find one series. The references are to res,
    # which survives a purge as a tombstone, so a key whose serial has gone is
    # recognizable as such rather than dangling.
    #
    # §5.4 gives a serial work one expression and one manifestation, so there is nothing
    # to look an expression up for: the work carries the inspiration and the manifestation
    # carries the issues.
    create table(:serial_keys, primary_key: false) do
      add :key, :text, primary_key: true
      add :serial_work_id, references(:res, type: :uuid, on_delete: :nothing)
      add :serial_manifestation_id, references(:res, type: :uuid, on_delete: :nothing)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:serial_keys, :a_serial_key_names_both_or_neither,
             check: "num_nulls(serial_work_id, serial_manifestation_id) IN (0, 2)"
           )
  end

  def down do
    drop table(:serial_keys)

    execute "DROP TRIGGER inspiration_is_not_work_part ON work_inspirations"
    execute "DROP FUNCTION reject_whole_part_inspiration()"
    execute "DROP TRIGGER work_part_is_not_inspiration ON work_parts"
    execute "DROP FUNCTION reject_inspiring_whole_part()"
    execute "DROP TRIGGER record_catalog_write ON work_inspirations"

    drop table(:work_inspirations)
  end
end
