defmodule Pluteus.Repo.Migrations.AdmitThroughTheProvider do
  use Ecto.Migration

  # spec-06 §6.1. Membership is the identity provider's decision: a person the
  # provider lets through is a member. What remains to distinguish in the
  # deployment is who administers it, and the deployment acting on itself.
  @roles ~w(system administrator member)
  @roles_with_guest @roles ++ ["guest"]

  def up do
    drop table(:guest_grants)

    execute("ALTER TABLE principals DROP CONSTRAINT role_must_be_known")
    execute("ALTER TABLE principals ADD CONSTRAINT role_must_be_known CHECK (#{in_list(@roles)})")

    execute(write_record(refuse_guests: false))
  end

  def down do
    execute(write_record(refuse_guests: true))

    execute("ALTER TABLE principals DROP CONSTRAINT role_must_be_known")

    execute(
      "ALTER TABLE principals ADD CONSTRAINT role_must_be_known CHECK (#{in_list(@roles_with_guest)})"
    )

    create table(:guest_grants, primary_key: false) do
      add :principal_id, references(:principals, type: :uuid, on_delete: :nothing),
        primary_key: true

      add :res_id, references(:res, type: :uuid, on_delete: :nothing), primary_key: true
      add :granted_by, references(:principals, type: :uuid, on_delete: :nothing), null: false
      add :granted_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end
  end

  defp write_record(refuse_guests: refuse_guests) do
    guest_clause =
      if refuse_guests do
        """
          IF acting_role = 'guest' THEN
            RAISE EXCEPTION 'guest % may not write to the catalog', actor USING ERRCODE = '42501';
          END IF;
        """
      else
        ""
      end

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
    #{guest_clause}
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

  defp in_list(values), do: "role IN (#{Enum.map_join(values, ", ", &"'#{&1}'")})"
end
