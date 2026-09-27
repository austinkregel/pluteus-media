defmodule Pluteus.Repo.Migrations.AttributeAPurgeToItsPrincipal do
  use Ecto.Migration

  # spec-06 §6.2 requires every catalog write to record the acting principal, and
  # a purge is one ([spec-07] §4.3). Its writes reach no feed entry, so the
  # tombstone is where the attribution lives — which suits it, being the permanent
  # record of the purge rather than a notification about it.
  #
  # No default and no backfill: a tombstone written before this records nobody,
  # and nothing can derive who it was. Where such rows exist the column cannot be
  # added and a person decides what to do about them, which is the right outcome.
  def change do
    alter table(:tombstones) do
      add :purged_by, references(:principals, type: :uuid, on_delete: :nothing), null: false
    end
  end
end
