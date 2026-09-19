defmodule Pluteus.Repo.Migrations.CreateCredits do
  use Ecto.Migration

  @roles ~w(artist album_artist)
  @provenances ~w(seeded automatic local)
  @agent_kinds ~w(person collective_agent)
  @stages ~w(acquire identify place normalize analyse purge credit)
  @prior_stages ~w(acquire identify place normalize analyse purge)

  def up do
    # spec-04 §6.4. Who a work's release credits, as it says it: LRM's
    # statement of responsibility. A credit names an agent only once the
    # agent's kind is known.
    create table(:credits, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :work_id, references(:works, type: :uuid, on_delete: :nothing), null: false
      add :role, :string, null: false
      add :position, :integer, null: false
      add :name, :text, null: false
      add :musicbrainz_id, :uuid
      add :agent_kind, :string
      add :provenance, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    alter table(:credits) do
      add :agent_id,
          references(:res,
            type: :uuid,
            column: :id,
            with: [agent_kind: :kind],
            on_delete: :nothing
          )
    end

    create index(:credits, [:work_id])
    create index(:credits, [:musicbrainz_id])
    create index(:credits, [:agent_id])

    create constraint(:credits, :credit_role_must_be_known, check: in_list("role", @roles))
    create constraint(:credits, :credit_position_is_positive, check: "position >= 1")

    create constraint(:credits, :credit_provenance_must_be_known,
             check: in_list("provenance", @provenances)
           )

    create constraint(:credits, :credited_agent_is_an_agent,
             check: "agent_kind IS NULL OR #{in_list("agent_kind", @agent_kinds)}"
           )

    create constraint(:credits, :credited_agent_link_is_whole,
             check: "(agent_id IS NULL) = (agent_kind IS NULL)"
           )

    execute """
    CREATE TRIGGER record_catalog_write
      AFTER INSERT OR UPDATE OR DELETE ON credits
      FOR EACH ROW EXECUTE FUNCTION record_catalog_write('id', 'work_id');
    """

    # What MusicBrainz said about each artist identifier a credit carries, and
    # the agent created for it. Recorded by ingest, and unique, so one agent is
    # created per identifier however many credits carry it.
    create table(:musicbrainz_artists, primary_key: false) do
      add :musicbrainz_id, :uuid, primary_key: true
      add :type, :string
      add :agent_id, references(:res, type: :uuid, on_delete: :nothing)
      add :attempts, :integer, null: false, default: 0
      add :looked_up_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    alter table(:ingest_findings) do
      add :musicbrainz_id, :uuid
    end

    drop constraint(:ingest_findings, :stage_must_be_known)
    create constraint(:ingest_findings, :stage_must_be_known, check: in_list("stage", @stages))

    drop constraint(:ingest_findings, :a_finding_has_a_subject)

    create constraint(:ingest_findings, :a_finding_has_a_subject,
             check:
               "num_nonnulls(acquisition_id, location, digital_item_id, input_id, musicbrainz_id) >= 1"
           )

    create unique_index(:ingest_findings, [:musicbrainz_id],
             where: "musicbrainz_id IS NOT NULL AND cleared_at IS NULL",
             name: :ingest_findings_one_open_per_musicbrainz_id_index
           )
  end

  def down do
    drop index(:ingest_findings, [:musicbrainz_id],
           name: :ingest_findings_one_open_per_musicbrainz_id_index
         )

    drop constraint(:ingest_findings, :a_finding_has_a_subject)

    create constraint(:ingest_findings, :a_finding_has_a_subject,
             check: "num_nonnulls(acquisition_id, location, digital_item_id, input_id) >= 1"
           )

    drop constraint(:ingest_findings, :stage_must_be_known)

    create constraint(:ingest_findings, :stage_must_be_known,
             check: in_list("stage", @prior_stages)
           )

    alter table(:ingest_findings) do
      remove :musicbrainz_id
    end

    drop table(:musicbrainz_artists)
    execute "DROP TRIGGER record_catalog_write ON credits"
    drop table(:credits)
  end

  defp in_list(column, values) do
    "#{column} IN (#{Enum.map_join(values, ", ", &"'#{&1}'")})"
  end
end
