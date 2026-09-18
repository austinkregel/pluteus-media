defmodule Pluteus.Repo.Migrations.CreateExistenceConstraints do
  use Ecto.Migration

  # §6.2 makes these creation-time obligations rather than perpetual invariants:
  # a work must come into existence with an expression, but deleting its last
  # expression later does not invalidate it. Both triggers therefore fire on
  # INSERT only.
  #
  # They are deferred because the parent row must exist before a child can
  # reference it, so the check cannot hold in the middle of the transaction that
  # writes both. Postgres has no deferrable CHECK, which is why these are
  # constraint triggers.

  def up do
    execute """
    CREATE FUNCTION work_must_have_expression() RETURNS trigger AS $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM expressions WHERE work_id = NEW.id) THEN
        RAISE EXCEPTION 'work % was created with no expression', NEW.id
          USING ERRCODE = '23514';
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE CONSTRAINT TRIGGER work_must_have_expression
      AFTER INSERT ON works
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION work_must_have_expression();
    """

    execute """
    CREATE FUNCTION expression_must_have_manifestation() RETURNS trigger AS $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM embodiments WHERE expression_id = NEW.id) THEN
        RAISE EXCEPTION 'expression % was created with no manifestation', NEW.id
          USING ERRCODE = '23514';
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE CONSTRAINT TRIGGER expression_must_have_manifestation
      AFTER INSERT ON expressions
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION expression_must_have_manifestation();
    """
  end

  def down do
    execute "DROP TRIGGER expression_must_have_manifestation ON expressions;"
    execute "DROP FUNCTION expression_must_have_manifestation();"
    execute "DROP TRIGGER work_must_have_expression ON works;"
    execute "DROP FUNCTION work_must_have_expression();"
  end
end
