defmodule Pluteus.Repo.Migrations.CreateAssetIntegrity do
  use Ecto.Migration

  @role_classes ~w(acquired normalized redundant derived)
  @essences ~w(lossy lossless)
  @outcomes ~w(verified mismatched unreadable)

  def change do
    # spec-01 §5.5 lets one asset carry several roles where they coincide on one
    # byte sequence, and forbids duplicating bytes to give each role an asset of
    # its own. A lossy record is its own normalized master (spec-03 §4.2), so it
    # is Acquired and Normalized at once, in one row, over one file.
    create table(:asset_roles, primary_key: false) do
      add :asset_id, references(:assets, type: :uuid, on_delete: :delete_all),
        primary_key: true,
        null: false

      add :role, :string, primary_key: true, null: false
      add :role_class, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:asset_roles, [:role_class])

    create constraint(:asset_roles, :role_class_must_be_known,
             check: in_list("role_class", @role_classes)
           )

    # Dropped by name rather than left to the column drop: Postgres removes a
    # check constraint and an index along with the column they read, which would
    # leave the migration that created them unable to drop them on the way back
    # down.
    execute(
      "DROP INDEX assets_role_class_index",
      "CREATE INDEX assets_role_class_index ON assets (role_class)"
    )

    execute(
      "ALTER TABLE assets DROP CONSTRAINT role_class_must_be_known",
      "ALTER TABLE assets ADD CONSTRAINT role_class_must_be_known" <>
        " CHECK (#{in_list("role_class", @role_classes)})"
    )

    alter table(:assets) do
      remove :role_class, :string
      remove :role, :string

      # spec-03 §3.2's required record. Nothing is defaulted: an asset whose
      # size or digest is unknown is an asset the household cannot check.
      add :size, :bigint, null: false
      add :digest, :text, null: false
      add :digest_algorithm, :string, null: false

      # spec-03 §6. Determined by inspecting the bytes, not the extension.
      add :format, :string, null: false

      # Whether the bytes already discarded information. spec-03 §4.2 turns on
      # it: lossy essence must not be re-encoded, because there is no fidelity
      # left to preserve and re-encoding only compounds generation loss.
      add :essence, :string, null: false

      # Nullable, and null means never verified — which spec-03 §5.3 reports as
      # unverified rather than treating as a fresh asset.
      add :verified_at, :utc_datetime_usec
      add :verification_interval_seconds, :bigint, null: false
    end

    create index(:assets, [:verified_at])
    create constraint(:assets, :essence_must_be_known, check: in_list("essence", @essences))
    create constraint(:assets, :size_is_not_negative, check: "size >= 0")

    create constraint(:assets, :verification_interval_is_positive,
             check: "verification_interval_seconds > 0"
           )

    # spec-03 §5.2. Every attempt is recorded, whether it succeeded or not: a
    # pass that fails to run is itself a finding, and is invisible where only
    # successes are kept.
    create table(:verifications, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :asset_id, references(:assets, type: :uuid, on_delete: :nothing), null: false
      add :outcome, :string, null: false
      add :occurred_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:verifications, [:asset_id, :occurred_at])

    create constraint(:verifications, :outcome_must_be_known,
             check: in_list("outcome", @outcomes)
           )
  end

  defp in_list(column, values) do
    "#{column} IN (#{Enum.map_join(values, ", ", &"'#{&1}'")})"
  end
end
