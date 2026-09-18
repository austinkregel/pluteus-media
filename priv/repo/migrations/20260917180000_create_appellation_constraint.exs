defmodule Pluteus.Repo.Migrations.CreateAppellationConstraint do
  use Ecto.Migration

  # §6.1. A nomen is itself a res, so naming every name has no end; a reified
  # address is identified by the region it selects, and a name per subtitle cue
  # would restate the selector. Every other kind carries a name.
  @exempt ~w(nomen address)

  def up do
    execute("""
    CREATE FUNCTION res_must_have_nomen() RETURNS trigger AS $$
    BEGIN
      IF NEW.kind IN (#{Enum.map_join(@exempt, ", ", &"'#{&1}'")}) THEN
        RETURN NULL;
      END IF;

      IF NOT EXISTS (SELECT 1 FROM nomens WHERE res_id = NEW.id) THEN
        RAISE EXCEPTION 'res % of kind % was created with no nomen', NEW.id, NEW.kind
          USING ERRCODE = '23514';
      END IF;

      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """)

    # §6.2 makes this a creation-time obligation rather than a perpetual
    # invariant: INSERT only, so that §7.5 can replace the whole shipped name
    # set without the removal being refused.
    execute("""
    CREATE CONSTRAINT TRIGGER res_must_have_nomen
      AFTER INSERT ON res
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION res_must_have_nomen();
    """)
  end

  def down do
    execute("DROP TRIGGER res_must_have_nomen ON res")
    execute("DROP FUNCTION res_must_have_nomen()")
  end
end
