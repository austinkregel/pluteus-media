defmodule Pluteus.Repo.Migrations.CreateOneNormalizedMaster do
  use Ecto.Migration

  # spec-04 §7: one live asset per digital item, or per part, holds the
  # Normalized role. A master being replaced is recycled in the same
  # transaction as its successor takes the role, so the check runs at commit
  # and counts only assets outside the bin. Restoring a replaced master from
  # the bin would make two, and is refused rather than allowed to stand.
  def up do
    execute """
    CREATE FUNCTION one_normalized_master() RETURNS trigger AS $$
    DECLARE
      subject uuid;
      holding uuid;
      part integer;
    BEGIN
      IF TG_TABLE_NAME = 'asset_roles' THEN
        subject := NEW.asset_id;
      ELSE
        subject := OLD.res_id;
      END IF;

      SELECT digital_item_id, part_sequence INTO holding, part FROM assets WHERE id = subject;

      IF holding IS NOT NULL AND (
        SELECT count(DISTINCT a.id)
        FROM assets a
        JOIN asset_roles r ON r.asset_id = a.id AND r.role_class = 'normalized'
        WHERE a.digital_item_id = holding
          AND a.part_sequence IS NOT DISTINCT FROM part
          AND NOT EXISTS (SELECT 1 FROM recycled_res b WHERE b.res_id = a.id)
      ) > 1 THEN
        RAISE EXCEPTION 'digital item % has more than one normalized master', holding
          USING ERRCODE = '23514', CONSTRAINT = 'one_normalized_master';
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE CONSTRAINT TRIGGER one_normalized_master
      AFTER INSERT ON asset_roles
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION one_normalized_master();
    """

    execute """
    CREATE CONSTRAINT TRIGGER one_normalized_master_on_restore
      AFTER DELETE ON recycled_res
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION one_normalized_master();
    """
  end

  def down do
    execute "DROP TRIGGER one_normalized_master_on_restore ON recycled_res"
    execute "DROP TRIGGER one_normalized_master ON asset_roles"
    execute "DROP FUNCTION one_normalized_master()"
  end
end
