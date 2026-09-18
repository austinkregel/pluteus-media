defmodule Pluteus.Repo.Migrations.CreateRes do
  use Ecto.Migration

  # LRM's eleven entities, plus the two extensions spec-01 §5.2 and §5.5 define.
  # `agent` is absent: LRM-E6 is strictly the union of person and collective
  # agent, so no row is ever an agent without being one of those two. `res` is
  # present because LRM-E1 admits instances belonging to no named subclass —
  # a concept used as the subject of a work, for one.
  @kinds ~w(
    res
    work
    expression
    manifestation
    item
    digital_item
    asset
    person
    collective_agent
    nomen
    place
    time_span
  )

  def change do
    create table(:res, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :kind, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Enforced in the database as well as the changeset: spec-01 §1.4 treats the
    # store as the authority on integrity, and a write that bypasses Ecto must
    # not be able to introduce a kind the model does not define.
    create constraint(:res, :kind_must_be_known,
             check: "kind IN (#{Enum.map_join(@kinds, ", ", &"'#{&1}'")})"
           )

    create index(:res, [:kind])
  end
end
