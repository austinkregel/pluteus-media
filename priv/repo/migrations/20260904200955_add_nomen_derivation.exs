defmodule Pluteus.Repo.Migrations.AddNomenDerivation do
  use Ecto.Migration

  # LRM-R17, listed among §6.1's required cardinalities. A transliteration, an
  # abbreviation, a shortened form: one nomen built from another.
  #
  # M to 1, so a scalar column rather than a join table — a nomen derives from
  # at most one other.
  #
  # LRM constrains it further than the cardinality shows: both nomens must be
  # appellations of the same res. That is carried by a composite foreign key on
  # (derived_from_id, res_id) rather than a trigger, so the database rejects a
  # derivation across two different res without any procedural code.

  def change do
    create unique_index(:nomens, [:id, :res_id], name: :nomens_id_res_id_index)

    alter table(:nomens) do
      add :derived_from_id,
          references(:nomens,
            type: :uuid,
            column: :id,
            with: [res_id: :res_id],
            on_delete: :nilify_all
          )
    end

    create index(:nomens, [:derived_from_id])
  end
end
