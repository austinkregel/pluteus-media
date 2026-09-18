defmodule Pluteus.Repo.Migrations.CreateWemi do
  use Ecto.Migration

  def change do
    create table(:works, primary_key: false) do
      add :id, references(:res, type: :uuid, on_delete: :nothing), primary_key: true
      timestamps(type: :utc_datetime_usec)
    end

    # LRM-R2 is 1 to M: an expression realizes exactly one work. A scalar column
    # is the constraint — there is no shape in which an expression names two.
    # The reference targets `works` rather than `res` so that an expression
    # cannot be pointed at a place or a nomen.
    create table(:expressions, primary_key: false) do
      add :id, references(:res, type: :uuid, on_delete: :nothing), primary_key: true

      add :work_id, references(:works, type: :uuid, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:expressions, [:work_id])

    create table(:manifestations, primary_key: false) do
      add :id, references(:res, type: :uuid, on_delete: :nothing), primary_key: true
      timestamps(type: :utc_datetime_usec)
    end

    # LRM-R4 is 1 to M, enforced the same way as LRM-R2.
    create table(:items, primary_key: false) do
      add :id, references(:res, type: :uuid, on_delete: :nothing), primary_key: true

      add :manifestation_id, references(:manifestations, type: :uuid, on_delete: :nothing),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:items, [:manifestation_id])

    # LRM-R3 is the only many-to-many among the four structural entities, which
    # is what makes an aggregate expressible: one manifestation embodying
    # several parallel expressions (§5.3).
    create table(:embodiments, primary_key: false) do
      add :expression_id, references(:expressions, type: :uuid, on_delete: :nothing), null: false

      add :manifestation_id, references(:manifestations, type: :uuid, on_delete: :nothing),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:embodiments, [:expression_id, :manifestation_id])
    create index(:embodiments, [:manifestation_id])
  end
end
