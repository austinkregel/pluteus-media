defmodule Pluteus.Repo.Migrations.HoldAChosenExpressionPerPrincipal do
  use Ecto.Migration

  # [spec-10] §8.1: where a work's significant attributes do not separate its expressions,
  # the surface asks once and records the answer. One row per principal per work, so a
  # second answer replaces the first rather than accumulating.
  #
  # It is a table rather than a preference key because the preference store holds one row per
  # (principal_id, key) and its key check lists every key: a key carrying a work identifier
  # could not pass it.
  #
  # The principal reference cascades, as [spec-10] §14.5's preferences do: a choice has no
  # meaning apart from the person whose it is. No change-feed trigger, for the same reasons —
  # a choice is not a catalog write, and §14.5 keeps it out of the consumption class too.
  #
  # `expression_id` carries a plain reference rather than the composite one that would pin it
  # to `work_id`. spec-03 §8.3's *same work* decision reparents an expression, and a
  # composite reference would make that decision fail wherever someone had chosen the
  # expression being moved. That the expression realizes the work is checked where the choice
  # is recorded.
  def up do
    create table(:principal_expression_choices, primary_key: false) do
      add :principal_id, references(:principals, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :work_id, references(:works, type: :uuid, on_delete: :delete_all), primary_key: true

      add :expression_id, references(:expressions, type: :uuid, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:principal_expression_choices, [:expression_id])
  end

  def down do
    drop table(:principal_expression_choices)
  end
end
