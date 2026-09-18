defmodule Pluteus.Repo.Migrations.CreateAnnotations do
  use Ecto.Migration

  @kinds_without ~w(
    res work expression manifestation item digital_item asset person
    collective_agent nomen place time_span address
  )
  @kinds @kinds_without ++ ["annotation"]

  @agent_kinds ~w(person collective_agent)

  def change do
    # spec-02 §3.1 makes an annotation a res.
    execute(
      "ALTER TABLE res DROP CONSTRAINT kind_must_be_known",
      "ALTER TABLE res ADD CONSTRAINT kind_must_be_known CHECK (#{in_list("kind", @kinds_without)})"
    )

    execute(
      "ALTER TABLE res ADD CONSTRAINT kind_must_be_known CHECK (#{in_list("kind", @kinds)})",
      "ALTER TABLE res DROP CONSTRAINT kind_must_be_known"
    )

    # spec-01 §6.1's third exemption. Derived annotations outnumber every other
    # row class by orders of magnitude, and a name for one would restate its
    # tool and body type.
    execute(appellation(~w(nomen address annotation)), appellation(~w(nomen address)))

    # spec-02 §4.2. A version is whatever distinguishes two builds, so version
    # strings carry no order of their own; `sequence` records the order the
    # system first saw each one, which is what "newer" and "before version X"
    # mean.
    create table(:tool_versions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tool, :string, null: false
      add :version, :string, null: false
      add :sequence, :bigserial, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tool_versions, [:tool, :version])
    create unique_index(:tool_versions, [:sequence])

    # spec-02 §4.1. A derivation names a tool, never an agent; the agent who ran
    # it is optional and accountable where provenance is disputed. `input` is the
    # res the tool ran over, which scopes supersession to one input.
    create table(:derivations, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :tool_version_id, references(:tool_versions, type: :uuid, on_delete: :nothing),
        null: false

      add :input_id, references(:res, type: :uuid, on_delete: :nothing), null: false
      add :parameters, :map, null: false
      add :derived_at, :utc_datetime_usec, null: false
      add :agent_kind, :string

      timestamps(type: :utc_datetime_usec)
    end

    alter table(:derivations) do
      add :agent_id,
          references(:res,
            type: :uuid,
            column: :id,
            with: [agent_kind: :kind],
            on_delete: :nothing
          )
    end

    create index(:derivations, [:tool_version_id])
    create index(:derivations, [:input_id])
    agent_constraints(:derivations)

    # spec-02 §3.3. An address a derivation produced — a segment boundary, a
    # detected scene — carries the derivation, so that nothing authored can be
    # anchored to it.
    alter table(:addresses) do
      add :derivation_id, references(:derivations, type: :uuid, on_delete: :nothing)
    end

    create index(:addresses, [:derivation_id])

    create table(:annotations, primary_key: false) do
      add :id, references(:res, type: :uuid, on_delete: :nothing), primary_key: true

      # An address for a region, or any res for the whole of it (spec-02 §3.1).
      add :target_id, references(:res, type: :uuid, on_delete: :nothing), null: false

      add :body_type, :string, null: false
      add :body, :map, null: false

      add :principal_id, references(:principals, type: :uuid, on_delete: :nothing)
      add :derivation_id, references(:derivations, type: :uuid, on_delete: :nothing)
      add :agent_kind, :string

      timestamps(type: :utc_datetime_usec)
    end

    alter table(:annotations) do
      add :agent_id,
          references(:res,
            type: :uuid,
            column: :id,
            with: [agent_kind: :kind],
            on_delete: :nothing
          )
    end

    create index(:annotations, [:target_id])
    create index(:annotations, [:derivation_id])
    create index(:annotations, [:principal_id])
    create index(:annotations, [:body_type])

    # spec-02 §3.2: authored or derived, exactly one.
    create constraint(:annotations, :provenance_is_a_principal_or_a_derivation,
             check: "(principal_id IS NULL) <> (derivation_id IS NULL)"
           )

    # spec-02 §3.4: an agent is someone on whose behalf a principal asserted.
    create constraint(:annotations, :agent_acts_through_a_principal,
             check: "agent_id IS NULL OR principal_id IS NOT NULL"
           )

    agent_constraints(:annotations)

    execute(
      """
      CREATE FUNCTION authored_annotation_targets_the_resource() RETURNS trigger AS $$
      BEGIN
        IF NEW.principal_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM addresses WHERE id = NEW.target_id AND derivation_id IS NOT NULL
        ) THEN
          RAISE EXCEPTION 'authored annotation % targets derived address %', NEW.id, NEW.target_id
            USING ERRCODE = '23514', CONSTRAINT = 'authored_annotation_targets_the_resource';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION authored_annotation_targets_the_resource()"
    )

    execute(
      """
      CREATE TRIGGER authored_annotation_targets_the_resource
        BEFORE INSERT OR UPDATE ON annotations
        FOR EACH ROW EXECUTE FUNCTION authored_annotation_targets_the_resource();
      """,
      "DROP TRIGGER authored_annotation_targets_the_resource ON annotations"
    )

    # The same rule from the other side: an address an authored annotation is
    # anchored to cannot be turned into a derived one afterwards.
    execute(
      """
      CREATE FUNCTION authored_anchor_stays_authored() RETURNS trigger AS $$
      BEGIN
        IF NEW.derivation_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM annotations WHERE target_id = NEW.id AND principal_id IS NOT NULL
        ) THEN
          RAISE EXCEPTION 'address % anchors an authored annotation', NEW.id
            USING ERRCODE = '23514', CONSTRAINT = 'authored_annotation_targets_the_resource';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION authored_anchor_stays_authored()"
    )

    execute(
      """
      CREATE TRIGGER authored_anchor_stays_authored
        BEFORE UPDATE OF derivation_id ON addresses
        FOR EACH ROW EXECUTE FUNCTION authored_anchor_stays_authored();
      """,
      "DROP TRIGGER authored_anchor_stays_authored ON addresses"
    )
  end

  defp agent_constraints(table) do
    create constraint(table, :agent_link_is_whole,
             check: "(agent_id IS NULL) = (agent_kind IS NULL)"
           )

    create constraint(table, :agent_is_an_agent,
             check: "agent_kind IS NULL OR #{in_list("agent_kind", @agent_kinds)}"
           )
  end

  defp appellation(exempt) do
    """
    CREATE OR REPLACE FUNCTION res_must_have_nomen() RETURNS trigger AS $$
    BEGIN
      IF NEW.kind IN (#{Enum.map_join(exempt, ", ", &"'#{&1}'")}) THEN
        RETURN NULL;
      END IF;

      IF NOT EXISTS (SELECT 1 FROM nomens WHERE res_id = NEW.id) THEN
        RAISE EXCEPTION 'res % of kind % was created with no nomen', NEW.id, NEW.kind
          USING ERRCODE = '23514';
      END IF;

      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """
  end

  defp in_list(column, values) do
    "#{column} IN (#{Enum.map_join(values, ", ", &"'#{&1}'")})"
  end
end
