defmodule Pluteus.Repo.Migrations.RecordWhatHappenedToTheHoldings do
  use Ecto.Migration

  # spec-01 §11.2's platform class: what happened to the holdings, visible to the
  # household. A table of its own rather than a class column on `events`, for four
  # reasons that each stand alone.
  #
  # `events.principal_id` is NOT NULL and every read of it is scoped by that
  # column, which is how §11.2's "that principal alone" is enforced; a
  # household-visible row in there would have to be exempted from the very column
  # that carries the rule. `events` also fires `notify_consumption`, so the row
  # would be pushed down a principal's private channel. The exported surface of
  # `Pluteus.Events` is asserted as a closed list precisely to prove it is
  # consumption-only, and that proof stays intact.
  #
  # The fourth is the strongest: criterion 42 forbids a platform event to carry,
  # or be combined into, what any principal consumed. With no principal-scoping
  # column there is nothing to combine, so the criterion holds by the shape of the
  # table rather than by a rule someone has to keep.
  #
  # `recorded_by` is who acted, which §11.2 says does not decide the class and
  # spec-06 §6.4 requires be visible — the household sees what was corrected and
  # by whom. It is not a scope: nothing reads this table through it.
  def change do
    create table(:platform_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :type, :string, null: false

      add :res_id, references(:res, type: :uuid, column: :id, on_delete: :nothing), null: false

      add :recorded_by, references(:principals, type: :uuid, on_delete: :nothing), null: false
      add :occurred_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:platform_events, [:occurred_at])
    create index(:platform_events, [:res_id])
  end
end
