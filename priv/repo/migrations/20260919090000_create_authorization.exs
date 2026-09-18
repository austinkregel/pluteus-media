defmodule Pluteus.Repo.Migrations.CreateAuthorization do
  use Ecto.Migration

  # spec-06 §6.1. The permissions each role carries are normative, so a role
  # arrives with a release and the set is closed here.
  @roles ~w(system administrator member guest)

  @agent_kinds ~w(person collective_agent)

  # Every table holding catalog content, with the columns that identify a row
  # in the write record. Principals, events, integrity records and the job
  # queue are not catalog writes and carry their own attribution where they
  # need one.
  @catalog %{
    "res" => ~w(id),
    "nomens" => ~w(id),
    "works" => ~w(id),
    "expressions" => ~w(id),
    "manifestations" => ~w(id),
    "items" => ~w(id),
    "digital_items" => ~w(id),
    "assets" => ~w(id),
    "addresses" => ~w(id),
    "annotations" => ~w(id),
    "embodiments" => ~w(expression_id manifestation_id),
    "work_parts" => ~w(whole_id part_id),
    "aggregations" => ~w(aggregating_expression_id aggregated_expression_id),
    "asset_roles" => ~w(asset_id role),
    "extents" => ~w(res_id unit),
    "associations" => ~w(subject_id object_id refinement),
    "work_creators" => ~w(work_id agent_id)
  }

  def change do
    create constraint(:principals, :role_must_be_known, check: in_list("role", @roles))

    # The deployment acting on itself is one principal, not several.
    create unique_index(:principals, [:role],
             where: "role = 'system'",
             name: :principals_one_system_index
           )

    # Removal from the trust boundary. The principal stays, so its events and
    # the catalog writes it made stay attributable.
    alter table(:principals) do
      add :retired_at, :utc_datetime_usec
    end

    # spec-06 §6.1: the System principal is never reached through §3's
    # authentication path, which is what having no identity mapping means.
    execute(
      """
      CREATE FUNCTION system_has_no_identity() RETURNS trigger AS $$
      BEGIN
        IF EXISTS (SELECT 1 FROM principals WHERE id = NEW.principal_id AND role = 'system') THEN
          RAISE EXCEPTION 'the System principal holds no external identity'
            USING ERRCODE = '23514', CONSTRAINT = 'system_has_no_identity';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION system_has_no_identity()"
    )

    execute(
      """
      CREATE TRIGGER system_has_no_identity
        BEFORE INSERT OR UPDATE ON principal_identities
        FOR EACH ROW EXECUTE FUNCTION system_has_no_identity();
      """,
      "DROP TRIGGER system_has_no_identity ON principal_identities"
    )

    # spec-06 §5. The household as trust boundary: one row, no name. Its one
    # link is to the collective agent the household is in the catalog, whose
    # nomens are the household's name.
    create table(:trust_boundary, primary_key: false) do
      add :singleton, :boolean, primary_key: true
      add :collective_agent_kind, :string
      add :onboarding_secret_digest, :text
      add :onboarding_issued_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    alter table(:trust_boundary) do
      add :collective_agent_id,
          references(:res,
            type: :uuid,
            column: :id,
            with: [collective_agent_kind: :kind],
            on_delete: :nothing
          )
    end

    create constraint(:trust_boundary, :there_is_one_trust_boundary, check: "singleton")

    create constraint(:trust_boundary, :household_link_is_whole,
             check: "(collective_agent_id IS NULL) = (collective_agent_kind IS NULL)"
           )

    create constraint(:trust_boundary, :household_is_a_collective_agent,
             check: "collective_agent_kind IS NULL OR collective_agent_kind = 'collective_agent'"
           )

    # spec-06 §4. A device is bound to whoever authenticated it and is never an
    # identity of its own.
    create table(:devices, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :principal_id, references(:principals, type: :uuid, on_delete: :nothing), null: false
      add :label, :string, null: false
      add :bound_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec
      add :revoked_by, references(:principals, type: :uuid, on_delete: :nothing)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:devices, [:principal_id])

    create constraint(:devices, :revocation_is_attributed,
             check: "(revoked_at IS NULL) = (revoked_by IS NULL)"
           )

    # spec-06 §6.1: what a guest may read. One res per grant; whether grants
    # also come per collection or bounded in time is spec-06's open question.
    create table(:guest_grants, primary_key: false) do
      add :principal_id, references(:principals, type: :uuid, on_delete: :nothing),
        primary_key: true

      add :res_id, references(:res, type: :uuid, on_delete: :nothing), primary_key: true
      add :granted_by, references(:principals, type: :uuid, on_delete: :nothing), null: false
      add :granted_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # spec-06 §6.6. Who did what to whom and when, and whether it worked. There
    # is deliberately no column that could carry what anyone consumed.
    create table(:audit_records, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :actor_id, references(:principals, type: :uuid, on_delete: :nothing), null: false
      add :subject_id, references(:principals, type: :uuid, on_delete: :nothing)
      add :operation, :string, null: false
      add :outcome, :string, null: false
      add :reason, :text
      add :occurred_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:audit_records, [:subject_id])
    create index(:audit_records, [:occurred_at])

    create constraint(:audit_records, :outcome_must_be_known,
             check: "outcome IN ('succeeded', 'failed')"
           )

    create constraint(:audit_records, :a_failure_says_why,
             check: "(outcome = 'failed') = (reason IS NOT NULL)"
           )

    # LRM-R5, WORK was created by AGENT, many to many.
    create table(:work_creators, primary_key: false) do
      add :work_id, references(:works, type: :uuid, on_delete: :nothing), null: false
      add :agent_kind, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    alter table(:work_creators) do
      add :agent_id,
          references(:res,
            type: :uuid,
            column: :id,
            with: [agent_kind: :kind],
            on_delete: :nothing
          ),
          null: false
    end

    create unique_index(:work_creators, [:work_id, :agent_id], name: :work_creators_pkey)
    create index(:work_creators, [:agent_id])

    create constraint(:work_creators, :creator_is_an_agent,
             check: in_list("agent_kind", @agent_kinds)
           )

    # spec-06 §6.2: every catalog write records the acting principal. The actor
    # is set for the transaction as `pluteus.actor`; a write with none, or by a
    # guest, is refused rather than recorded against nobody.
    create table(:catalog_writes) do
      add :principal_id, references(:principals, type: :uuid, on_delete: :nothing), null: false
      add :table_name, :string, null: false
      add :operation, :string, null: false
      add :row_key, :map, null: false
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create index(:catalog_writes, [:principal_id])
    create index(:catalog_writes, [:occurred_at])

    execute(
      """
      CREATE FUNCTION record_catalog_write() RETURNS trigger AS $$
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

        IF acting_role = 'guest' THEN
          RAISE EXCEPTION 'guest % may not write to the catalog', actor USING ERRCODE = '42501';
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
      """,
      "DROP FUNCTION record_catalog_write()"
    )

    for {table, key} <- @catalog do
      execute(
        """
        CREATE TRIGGER record_catalog_write
          AFTER INSERT OR UPDATE OR DELETE ON #{table}
          FOR EACH ROW EXECUTE FUNCTION record_catalog_write(#{Enum.map_join(key, ", ", &"'#{&1}'")});
        """,
        "DROP TRIGGER record_catalog_write ON #{table}"
      )
    end
  end

  defp in_list(column, values) do
    "#{column} IN (#{Enum.map_join(values, ", ", &"'#{&1}'")})"
  end
end
