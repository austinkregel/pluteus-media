defmodule Pluteus.Repo.Migrations.CreatePreservationObligations do
  use Ecto.Migration

  @signals ~w(digest perceptual external_identifier)
  @decisions ~w(same_holding distinct)

  def change do
    # spec-01 §5.5: every asset carries at least one role. Deferred, since the
    # roles are written after the asset in the same transaction.
    execute(
      """
      CREATE FUNCTION asset_must_have_role() RETURNS trigger AS $$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM asset_roles WHERE asset_id = NEW.id) THEN
          RAISE EXCEPTION 'asset % was created with no role', NEW.id
            USING ERRCODE = '23514';
        END IF;
        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION asset_must_have_role()"
    )

    execute(
      """
      CREATE CONSTRAINT TRIGGER asset_must_have_role
        AFTER INSERT ON assets
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW EXECUTE FUNCTION asset_must_have_role();
      """,
      "DROP TRIGGER asset_must_have_role ON assets"
    )

    # spec-03 §4.3. The proof that a recompression reproduces the original it
    # replaces. Both references are to res, not to assets, because the
    # original's asset row is purged in time and this record must outlive it.
    create table(:reconstructions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :original_id, references(:res, type: :uuid, on_delete: :nothing), null: false
      add :recompression_id, references(:res, type: :uuid, on_delete: :nothing), null: false

      add :digest, :text, null: false
      add :digest_algorithm, :string, null: false

      add :verified_by, references(:principals, type: :uuid, on_delete: :nothing), null: false

      add :verified_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:reconstructions, [:original_id])
    create index(:reconstructions, [:recompression_id])

    # spec-03 §8. A candidate is a pair and a signal; a decision is a person's.
    # The pair is stored in one order so that detecting it again finds the row
    # already there, decided or not, instead of raising it a second time.
    create table(:duplicate_candidates, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :left_id, references(:res, type: :uuid, on_delete: :nothing), null: false
      add :right_id, references(:res, type: :uuid, on_delete: :nothing), null: false
      add :signal, :string, null: false
      add :detected_at, :utc_datetime_usec, null: false

      add :decision, :string
      add :decided_by, references(:principals, type: :uuid, on_delete: :nothing)
      add :decided_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:duplicate_candidates, [:left_id, :right_id, :signal])
    create index(:duplicate_candidates, [:right_id])

    create constraint(:duplicate_candidates, :pair_is_ordered, check: "left_id < right_id")

    create constraint(:duplicate_candidates, :signal_must_be_known,
             check: "signal IN (#{Enum.map_join(@signals, ", ", &"'#{&1}'")})"
           )

    create constraint(:duplicate_candidates, :decision_must_be_known,
             check:
               "decision IS NULL OR decision IN (#{Enum.map_join(@decisions, ", ", &"'#{&1}'")})"
           )

    create constraint(:duplicate_candidates, :decision_is_attributed,
             check:
               "(decision IS NULL) = (decided_by IS NULL) AND (decision IS NULL) = (decided_at IS NULL)"
           )
  end
end
