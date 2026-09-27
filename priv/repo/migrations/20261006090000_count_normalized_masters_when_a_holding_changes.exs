defmodule Pluteus.Repo.Migrations.CountNormalizedMastersWhenAHoldingChanges do
  use Ecto.Migration

  # spec-04 §7 allows one live normalized master per digital item, and the count
  # was reached only when a role was granted or a master came back out of the
  # bin. An asset changing which digital item holds it reaches the same count by
  # a third route — spec-03 §8.3's *same holding* moves the assets of one holding
  # under another — and two masters could meet under the survivor with nothing
  # raised.
  #
  # The subject is read from the row the trigger fired on, so `assets` needs a
  # branch of its own: the moved asset is the one to count around.
  def up do
    execute replace_function("NEW.id")

    execute """
    CREATE CONSTRAINT TRIGGER one_normalized_master_on_reholding
      AFTER UPDATE OF digital_item_id ON assets
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION one_normalized_master();
    """
  end

  def down do
    execute "DROP TRIGGER one_normalized_master_on_reholding ON assets"
    execute replace_function(nil)
  end

  # Passing nil restores the two-branch form, where anything that is not
  # `asset_roles` is `recycled_res`.
  defp replace_function(assets_subject) do
    """
    CREATE OR REPLACE FUNCTION one_normalized_master() RETURNS trigger AS $$
    DECLARE
      subject uuid;
      holding uuid;
      part integer;
    BEGIN
      IF TG_TABLE_NAME = 'asset_roles' THEN
        subject := NEW.asset_id;
      #{assets_branch(assets_subject)}ELSE
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
  end

  defp assets_branch(nil), do: ""

  defp assets_branch(subject) do
    """
    ELSIF TG_TABLE_NAME = 'assets' THEN
        subject := #{subject};
      \
    """
  end
end
