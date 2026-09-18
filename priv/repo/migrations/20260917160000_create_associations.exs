defmodule Pluteus.Repo.Migrations.CreateAssociations do
  use Ecto.Migration

  def change do
    # LRM-R1, the association between any two res. §6.3 and §7.5 both refine it
    # rather than declaring relations of their own, so one table carries every
    # refinement and the refinement itself names which.
    #
    # There is no check on `refinement`. §17 makes the refinement types seed
    # data, and a check constraint would turn a release's vocabulary into a
    # migration.
    create table(:associations, primary_key: false) do
      add :subject_id, references(:res, type: :uuid, on_delete: :nothing), null: false
      add :object_id, references(:res, type: :uuid, on_delete: :nothing), null: false
      add :refinement, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:associations, [:subject_id, :object_id, :refinement],
             name: :associations_triple_index
           )

    create index(:associations, [:object_id])

    create constraint(:associations, :res_is_not_associated_with_itself,
             check: "subject_id <> object_id"
           )
  end
end
