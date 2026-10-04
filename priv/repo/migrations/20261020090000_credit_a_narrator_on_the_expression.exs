defmodule Pluteus.Repo.Migrations.CreditANarratorOnTheExpression do
  use Ecto.Migration

  @roles ~w(artist album_artist author narrator)

  def up do
    # spec-04 §6.9 criterion 38. A narration is an expression of the text, and the narrator
    # is credited on that expression while the author is credited on the work. A credit
    # could only name a work, so the narrator had nowhere to go.
    alter table(:credits) do
      add :expression_id, references(:expressions, type: :uuid, on_delete: :nothing)
    end

    execute "ALTER TABLE credits ALTER COLUMN work_id DROP NOT NULL"

    create index(:credits, [:expression_id])

    # One or the other, never both and never neither: a credit is about one res, and which
    # level it is about is what distinguishes an author from a narrator.
    create constraint(:credits, :a_credit_names_a_work_or_an_expression,
             check: "num_nonnulls(work_id, expression_id) = 1"
           )

    drop constraint(:credits, :credit_role_must_be_known)

    create constraint(:credits, :credit_role_must_be_known, check: in_list("role", @roles))

    # The feed takes a credit's res from whichever level it names. Without the new column
    # here, an expression credit would be recorded as a write naming no res at all, and no
    # surface watching that expression would hear of it.
    execute "DROP TRIGGER record_catalog_write ON credits"

    execute """
    CREATE TRIGGER record_catalog_write
      AFTER INSERT OR UPDATE OR DELETE ON credits
      FOR EACH ROW EXECUTE FUNCTION
        record_catalog_write('{id,work_id}', '{work_id,expression_id,agent_id}');
    """
  end

  def down do
    execute "DROP TRIGGER record_catalog_write ON credits"

    execute """
    CREATE TRIGGER record_catalog_write
      AFTER INSERT OR UPDATE OR DELETE ON credits
      FOR EACH ROW EXECUTE FUNCTION record_catalog_write('{id,work_id}', '{work_id,agent_id}');
    """

    drop constraint(:credits, :credit_role_must_be_known)

    create constraint(:credits, :credit_role_must_be_known,
             check: in_list("role", ~w(artist album_artist))
           )

    drop constraint(:credits, :a_credit_names_a_work_or_an_expression)

    # A credit naming an expression has no work to name, and inventing one would say an
    # author wrote what a narrator read.
    execute "DELETE FROM credits WHERE work_id IS NULL"
    execute "ALTER TABLE credits ALTER COLUMN work_id SET NOT NULL"

    alter table(:credits) do
      remove :expression_id
    end
  end

  defp in_list(column, values), do: "#{column} IN (#{Enum.map_join(values, ", ", &"'#{&1}'")})"
end
