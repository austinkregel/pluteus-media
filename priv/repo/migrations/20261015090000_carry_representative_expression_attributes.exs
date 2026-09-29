defmodule Pluteus.Repo.Migrations.CarryRepresentativeExpressionAttributes do
  use Ecto.Migration

  # spec-01 §6.5: a work may carry representative expression attributes, and an expression
  # carries values of the same attributes. The distance between the two is what orders
  # competing expressions of one work (§8.6).
  #
  # A map rather than a column each, because the attribute set differs per category of work
  # and a column each would be a migration per category. Which keys a map may hold is the
  # registry's, and the changeset refuses one the work's type does not name.
  #
  # An empty map is the absence of any recorded attribute, which is what §6.5's "MAY carry"
  # admits. There is no second spelling of it: a null would say the same thing.
  def up do
    alter table(:works) do
      add :representative_attributes, :map, null: false, default: "{}"
    end

    alter table(:expressions) do
      add :significant_attributes, :map, null: false, default: "{}"
    end
  end

  def down do
    alter table(:works) do
      remove :representative_attributes
    end

    alter table(:expressions) do
      remove :significant_attributes
    end
  end
end
