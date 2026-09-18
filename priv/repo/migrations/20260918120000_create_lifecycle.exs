defmodule Pluteus.Repo.Migrations.CreateLifecycle do
  use Ecto.Migration

  def change do
    # §14.3. Recycling cascades downward as one grouped operation with one
    # restoration, so the operation is a row of its own and the res it took
    # are recorded against it.
    create table(:recyclings, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :root_id, references(:res, type: :uuid, on_delete: :nothing), null: false

      add :recycled_by, references(:principals, type: :uuid, on_delete: :nothing), null: false

      add :recycled_at, :utc_datetime_usec, null: false
      add :purge_after, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:recyclings, [:purge_after])

    create constraint(:recyclings, :purge_follows_recycling, check: "purge_after > recycled_at")

    # The res is the key, so no res can sit in two recyclings at once.
    create table(:recycled_res, primary_key: false) do
      add :res_id, references(:res, type: :uuid, on_delete: :nothing), primary_key: true

      add :recycling_id, references(:recyclings, type: :uuid, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:recycled_res, [:recycling_id])

    # §14.3 requires the identifier, the entity class and the time of purge to
    # outlive the entity indefinitely. The res row itself is kept, so its
    # primary key refuses the identifier to anything minted afterwards; this row
    # records that it was purged and when. The kind is repeated under a
    # composite key so the tombstone states the class on its own and cannot
    # disagree with the res.
    create table(:tombstones, primary_key: false) do
      add :kind, :string, null: false

      add :purged_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    alter table(:tombstones) do
      add :res_id,
          references(:res,
            type: :uuid,
            column: :id,
            with: [kind: :kind],
            on_delete: :nothing
          ),
          primary_key: true
    end
  end
end
