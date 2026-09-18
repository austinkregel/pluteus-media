defmodule Pluteus.Repo.Migrations.CreatePlacement do
  use Ecto.Migration

  @provenances ~w(seeded automatic local)

  def up do
    # spec-01 §7.5 and §17. A category is a value in a categorization scheme,
    # held per res and per provenance, so an automatic category and a member's
    # correction of it are separate rows and the correction wins by preference.
    create table(:categories, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :res_id, references(:res, type: :uuid, on_delete: :nothing), null: false
      add :scheme, :string, null: false
      add :value, :string, null: false
      add :provenance, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:categories, [:res_id, :scheme, :provenance])

    create constraint(:categories, :category_provenance_must_be_known,
             check: "provenance IN (#{Enum.map_join(@provenances, ", ", &"'#{&1}'")})"
           )

    execute """
    CREATE TRIGGER record_catalog_write
      AFTER INSERT OR UPDATE OR DELETE ON categories
      FOR EACH ROW EXECUTE FUNCTION record_catalog_write('res_id', 'scheme', 'provenance');
    """

    # spec-04 §6.4. The key each release was grouped by, recorded by ingest
    # outside the catalog. The key is unique, so two placements with one key
    # serialize on it and create one release. The references are to res, which
    # survives a purge as a tombstone, so a key whose release has gone is
    # recognizable as such rather than dangling.
    create table(:release_keys, primary_key: false) do
      add :key, :text, primary_key: true
      add :release_manifestation_id, references(:res, type: :uuid, on_delete: :nothing)
      add :release_expression_id, references(:res, type: :uuid, on_delete: :nothing)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:release_keys, :a_release_key_names_both_or_neither,
             check: "num_nulls(release_manifestation_id, release_expression_id) IN (0, 2)"
           )

    # spec-04 §8.1. The digital item whose normalized master analysis of a
    # manifestation reads: the earliest placed, until a member names another.
    create table(:analysis_sources, primary_key: false) do
      add :manifestation_id, references(:res, type: :uuid, on_delete: :nothing), primary_key: true

      add :digital_item_id, references(:res, type: :uuid, on_delete: :nothing), null: false
      add :named_by, references(:principals, type: :uuid, on_delete: :nothing)

      timestamps(type: :utc_datetime_usec)
    end

    # The acquisition record outlives placement and every later purge, so it
    # names the digital item through res, whose row survives as a tombstone.
    repoint(:acquisitions, :digital_item_id, :res)
    repoint(:ingest_findings, :digital_item_id, :res)
  end

  def down do
    repoint(:ingest_findings, :digital_item_id, :digital_items)
    repoint(:acquisitions, :digital_item_id, :digital_items)

    drop table(:analysis_sources)
    drop table(:release_keys)

    execute "DROP TRIGGER record_catalog_write ON categories"
    drop table(:categories)
  end

  defp repoint(table, column, to) do
    execute "ALTER TABLE #{table} DROP CONSTRAINT #{table}_#{column}_fkey"

    execute """
    ALTER TABLE #{table} ADD CONSTRAINT #{table}_#{column}_fkey
      FOREIGN KEY (#{column}) REFERENCES #{to}(id)
    """
  end
end
