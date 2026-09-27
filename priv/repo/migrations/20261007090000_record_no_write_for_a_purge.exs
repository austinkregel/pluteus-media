defmodule Pluteus.Repo.Migrations.RecordNoWriteForAPurge do
  use Ecto.Migration

  # spec-01 §14.2 and [spec-07] §5.1: a purge produces no change notification.
  # Propagation announces that something changed and never that something is
  # absent, and the recycling that preceded the purge was the entry a client
  # needed; one that missed it is answered 410 on its next request.
  #
  # The setting is read after the acting principal is established, not before, so
  # a write attributed to nobody is still refused. Only the function changes: the
  # triggers keep the two arguments they were created with.
  def up, do: execute(recording_function(suppressible: true))

  def down, do: execute(recording_function(suppressible: false))

  defp recording_function(suppressible: suppressible) do
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
    #{unrecorded_check(suppressible)}
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

  defp unrecorded_check(false), do: ""

  defp unrecorded_check(true) do
    """

      IF coalesce(current_setting('pluteus.unrecorded', true), '') <> '' THEN
        RETURN NULL;
      END IF;
    """
  end
end
