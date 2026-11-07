defmodule Pluteus.Repo.Migrations.RecordWhichLayerAnAssociationBelongsTo do
  use Ecto.Migration

  # spec-05 §3.2 and §8.7: matching may replace an association it wrote, when a later
  # snapshot answers differently, and must never touch one a member asserted. An
  # association therefore says which layer it belongs to, in the vocabulary a nomen uses.
  #
  # Every association so far was written by placement, which acts as the System
  # principal, so every existing row is automatic and is marked so under that principal:
  # the trigger refuses a catalog write with no actor. A new row states its own layer,
  # and there is no default to stand in for one that does not.
  def up do
    alter table(:associations) do
      add :provenance, :text
    end

    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM associations) THEN
        PERFORM set_config(
          'pluteus.actor',
          (SELECT id::text FROM principals WHERE role = 'system'),
          true
        );

        UPDATE associations SET provenance = 'automatic';
      END IF;
    END $$;
    """

    execute "ALTER TABLE associations ALTER COLUMN provenance SET NOT NULL"

    create constraint(:associations, :association_provenance_is_known,
             check: "provenance IN ('seeded', 'automatic', 'local')"
           )
  end

  def down do
    drop constraint(:associations, :association_provenance_is_known)

    alter table(:associations) do
      remove :provenance
    end
  end
end
