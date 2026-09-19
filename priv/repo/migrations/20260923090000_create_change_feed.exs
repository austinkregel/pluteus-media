defmodule Pluteus.Repo.Migrations.CreateChangeFeed do
  use Ecto.Migration

  # spec-07 §5.1. Each catalog table with the columns that identify a row, and
  # the columns that hold a res identifier: the feed names every res a write
  # touched, so a client knows what to fetch again.
  #
  # recycled_res and tombstones are here because recycling, restoring and
  # purging change what a res answers, and a client reconciling from the feed
  # must learn of it.
  @catalog %{
    "res" => {~w(id), ~w(id)},
    "nomens" => {~w(id), ~w(id res_id assigner_id derived_from_id)},
    "works" => {~w(id), ~w(id)},
    "expressions" => {~w(id), ~w(id work_id)},
    "manifestations" => {~w(id), ~w(id)},
    "items" => {~w(id), ~w(id manifestation_id)},
    "digital_items" => {~w(id), ~w(id manifestation_id)},
    "assets" => {~w(id), ~w(id digital_item_id)},
    "addresses" => {~w(id), ~w(id target_id)},
    "annotations" => {~w(id), ~w(id target_id agent_id)},
    "embodiments" => {~w(expression_id manifestation_id), ~w(expression_id manifestation_id)},
    "work_parts" => {~w(whole_id part_id), ~w(whole_id part_id)},
    "aggregations" =>
      {~w(aggregating_expression_id aggregated_expression_id),
       ~w(aggregating_expression_id aggregated_expression_id)},
    "asset_roles" => {~w(asset_id role), ~w(asset_id)},
    "extents" => {~w(res_id unit), ~w(res_id)},
    "associations" => {~w(subject_id object_id refinement), ~w(subject_id object_id)},
    "work_creators" => {~w(work_id agent_id), ~w(work_id agent_id)},
    "manifestation_parts" => {~w(whole_id part_id), ~w(whole_id part_id)},
    "categories" => {~w(res_id scheme provenance), ~w(res_id)},
    "credits" => {~w(id work_id), ~w(work_id agent_id)},
    "recycled_res" => {~w(res_id), ~w(res_id)},
    "tombstones" => {~w(res_id), ~w(res_id)}
  }

  @recorded_before Map.keys(@catalog) -- ~w(recycled_res tombstones)

  # spec-07 §5.2. The consumption data a principal's own devices are told of.
  @consumption ~w(events resume_positions)

  def up do
    alter table(:catalog_writes) do
      add :res_ids, {:array, :uuid}
    end

    execute(recording_function())

    for table <- @recorded_before do
      execute("DROP TRIGGER record_catalog_write ON #{table}")
    end

    for {table, {key, res}} <- @catalog do
      execute("""
      CREATE TRIGGER record_catalog_write
        AFTER INSERT OR UPDATE OR DELETE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION record_catalog_write('#{array(key)}', '#{array(res)}');
      """)
    end

    for {table, {key, res}} <- @catalog, table in @recorded_before do
      execute(backfill(table, key, res))
    end

    execute("ALTER TABLE catalog_writes ALTER COLUMN res_ids SET NOT NULL")

    execute("""
    CREATE FUNCTION notify_consumption() RETURNS trigger AS $$
    DECLARE
      principal uuid;
    BEGIN
      IF TG_OP = 'DELETE' THEN
        principal := OLD.principal_id;
      ELSE
        principal := NEW.principal_id;
      END IF;

      PERFORM pg_notify('consumption', principal::text || ' ' || TG_TABLE_NAME);
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """)

    for table <- @consumption do
      execute("""
      CREATE TRIGGER notify_consumption
        AFTER INSERT OR UPDATE OR DELETE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION notify_consumption();
      """)
    end
  end

  def down do
    for table <- @consumption do
      execute("DROP TRIGGER notify_consumption ON #{table}")
    end

    execute("DROP FUNCTION notify_consumption()")

    for table <- Map.keys(@catalog) do
      execute("DROP TRIGGER record_catalog_write ON #{table}")
    end

    execute(keyed_function())

    for {table, {key, _res}} <- @catalog, table in @recorded_before do
      execute("""
      CREATE TRIGGER record_catalog_write
        AFTER INSERT OR UPDATE OR DELETE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION record_catalog_write(#{Enum.map_join(key, ", ", &"'#{&1}'")});
      """)
    end

    alter table(:catalog_writes) do
      remove :res_ids
    end
  end

  defp array(columns), do: "{" <> Enum.join(columns, ",") <> "}"

  # A recorded write takes its res from the written row where that row still
  # exists, and from its key where it does not. A deleted row's res outside its
  # key are not recoverable.
  defp backfill(table, key, res) do
    populated = "jsonb_populate_record(NULL::#{table}, w.row_key)"
    match = Enum.map_join(key, " AND ", &"t.#{&1} = (#{populated}).#{&1}")

    values =
      Enum.map_join(res, ", ", fn column ->
        "COALESCE((SELECT t.#{column} FROM #{table} t WHERE #{match}), (#{populated}).#{column})"
      end)

    """
    UPDATE catalog_writes w
      SET res_ids = ARRAY(SELECT DISTINCT v FROM unnest(ARRAY[#{values}]::uuid[]) v WHERE v IS NOT NULL)
      WHERE w.table_name = '#{table}'
    """
  end

  defp recording_function do
    """
    CREATE OR REPLACE FUNCTION record_catalog_write() RETURNS trigger AS $$
    DECLARE
      actor text := current_setting('pluteus.actor', true);
      acting_role text;
      key_columns text[] := TG_ARGV[0]::text[];
      res_columns text[] := TG_ARGV[1]::text[];
      written jsonb;
      touched jsonb[];
      key jsonb := '{}'::jsonb;
      res_ids uuid[] := '{}';
      row_written jsonb;
      column_name text;
    BEGIN
      IF actor IS NULL OR actor = '' THEN
        RAISE EXCEPTION 'catalog write to % with no acting principal', TG_TABLE_NAME
          USING ERRCODE = '42501';
      END IF;

      SELECT role INTO acting_role FROM principals WHERE id = actor::uuid;

      IF acting_role IS NULL THEN
        RAISE EXCEPTION 'acting principal % does not exist', actor USING ERRCODE = '42501';
      END IF;

      IF TG_OP = 'DELETE' THEN
        written := to_jsonb(OLD);
        touched := ARRAY[written];
      ELSIF TG_OP = 'UPDATE' THEN
        written := to_jsonb(NEW);
        touched := ARRAY[to_jsonb(OLD), written];
      ELSE
        written := to_jsonb(NEW);
        touched := ARRAY[written];
      END IF;

      FOREACH column_name IN ARRAY key_columns LOOP
        key := key || jsonb_build_object(column_name, written -> column_name);
      END LOOP;

      FOREACH row_written IN ARRAY touched LOOP
        FOREACH column_name IN ARRAY res_columns LOOP
          IF row_written ->> column_name IS NOT NULL
             AND NOT (row_written ->> column_name)::uuid = ANY (res_ids) THEN
            res_ids := res_ids || (row_written ->> column_name)::uuid;
          END IF;
        END LOOP;
      END LOOP;

      INSERT INTO catalog_writes (principal_id, table_name, operation, row_key, res_ids, occurred_at)
        VALUES (actor::uuid, TG_TABLE_NAME, TG_OP, key, res_ids, clock_timestamp());

      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """
  end

  defp keyed_function do
    """
    CREATE OR REPLACE FUNCTION record_catalog_write() RETURNS trigger AS $$
    DECLARE
      actor text := current_setting('pluteus.actor', true);
      acting_role text;
      written jsonb;
      key jsonb := '{}'::jsonb;
      column_name text;
    BEGIN
      IF actor IS NULL OR actor = '' THEN
        RAISE EXCEPTION 'catalog write to % with no acting principal', TG_TABLE_NAME
          USING ERRCODE = '42501';
      END IF;

      SELECT role INTO acting_role FROM principals WHERE id = actor::uuid;

      IF acting_role IS NULL THEN
        RAISE EXCEPTION 'acting principal % does not exist', actor USING ERRCODE = '42501';
      END IF;

      IF TG_OP = 'DELETE' THEN
        written := to_jsonb(OLD);
      ELSE
        written := to_jsonb(NEW);
      END IF;

      FOREACH column_name IN ARRAY TG_ARGV LOOP
        key := key || jsonb_build_object(column_name, written -> column_name);
      END LOOP;

      INSERT INTO catalog_writes (principal_id, table_name, operation, row_key, occurred_at)
        VALUES (actor::uuid, TG_TABLE_NAME, TG_OP, key, clock_timestamp());

      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """
  end
end
