defmodule Pluteus.Repo.Migrations.CreateWorkRelations do
  use Ecto.Migration

  def up do
    # LRM-R18, whole-part between works. Applies where the component-to-whole
    # relation is inherent to the works themselves — a movement of a concerto, a
    # novel within a trilogy.
    create table(:work_parts, primary_key: false) do
      add :whole_id, references(:works, type: :uuid, on_delete: :nothing), null: false
      add :part_id, references(:works, type: :uuid, on_delete: :nothing), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:work_parts, [:whole_id, :part_id])
    create index(:work_parts, [:part_id])
    create constraint(:work_parts, :part_is_not_the_whole, check: "whole_id <> part_id")

    # LRM-R25. Aggregation happens between expressions, never between works:
    # §5.3 holds that an aggregating work carries only selection and arrangement
    # criteria and does not contain what it aggregates.
    create table(:aggregations, primary_key: false) do
      add :aggregating_expression_id, references(:expressions, type: :uuid, on_delete: :nothing),
        null: false

      add :aggregated_expression_id, references(:expressions, type: :uuid, on_delete: :nothing),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:aggregations, [:aggregating_expression_id, :aggregated_expression_id],
             name: :aggregations_pair_index
           )

    create index(:aggregations, [:aggregated_expression_id])

    create constraint(:aggregations, :expression_does_not_aggregate_itself,
             check: "aggregating_expression_id <> aggregated_expression_id"
           )

    # §5.3's prohibition. Whether a work aggregates another is a fact about
    # their expressions, so the check joins through them. It is enforced from
    # both sides because either relation may be written first.
    execute """
    CREATE FUNCTION aggregation_is_not_whole_part(whole uuid, part uuid)
    RETURNS boolean AS $$
      SELECT NOT EXISTS (
        SELECT 1
        FROM aggregations a
        JOIN expressions aggregating ON aggregating.id = a.aggregating_expression_id
        JOIN expressions aggregated ON aggregated.id = a.aggregated_expression_id
        WHERE aggregating.work_id = whole
          AND aggregated.work_id = part
      );
    $$ LANGUAGE sql STABLE;
    """

    execute """
    CREATE FUNCTION reject_aggregating_whole_part() RETURNS trigger AS $$
    BEGIN
      IF NOT aggregation_is_not_whole_part(NEW.whole_id, NEW.part_id) THEN
        RAISE EXCEPTION
          'work % aggregates work %; aggregation is not a whole-part relation',
          NEW.whole_id, NEW.part_id
          USING ERRCODE = '23514';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER work_part_is_not_aggregation
      BEFORE INSERT OR UPDATE ON work_parts
      FOR EACH ROW EXECUTE FUNCTION reject_aggregating_whole_part();
    """

    execute """
    CREATE FUNCTION reject_whole_part_aggregation() RETURNS trigger AS $$
    DECLARE
      aggregating_work uuid;
      aggregated_work uuid;
    BEGIN
      SELECT work_id INTO aggregating_work
        FROM expressions WHERE id = NEW.aggregating_expression_id;
      SELECT work_id INTO aggregated_work
        FROM expressions WHERE id = NEW.aggregated_expression_id;

      IF EXISTS (
        SELECT 1 FROM work_parts
        WHERE whole_id = aggregating_work AND part_id = aggregated_work
      ) THEN
        RAISE EXCEPTION
          'work % already has work % as a part; it cannot also aggregate it',
          aggregating_work, aggregated_work
          USING ERRCODE = '23514';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER aggregation_is_not_work_part
      BEFORE INSERT OR UPDATE ON aggregations
      FOR EACH ROW EXECUTE FUNCTION reject_whole_part_aggregation();
    """
  end

  def down do
    execute "DROP TRIGGER aggregation_is_not_work_part ON aggregations;"
    execute "DROP FUNCTION reject_whole_part_aggregation();"
    execute "DROP TRIGGER work_part_is_not_aggregation ON work_parts;"
    execute "DROP FUNCTION reject_aggregating_whole_part();"
    execute "DROP FUNCTION aggregation_is_not_whole_part(uuid, uuid);"

    drop table(:aggregations)
    drop table(:work_parts)
  end
end
