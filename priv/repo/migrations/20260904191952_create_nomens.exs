defmodule Pluteus.Repo.Migrations.CreateNomens do
  use Ecto.Migration

  def change do
    create table(:nomens, primary_key: false) do
      # A nomen is itself a res (spec-01 §7.1), so its identifier is a row in
      # `res` rather than an independent key space. That is what lets a nomen
      # carry nomens of its own.
      add :id, references(:res, type: :uuid, on_delete: :nothing), primary_key: true

      # LRM-R13 is 1 to M and a nomen is the appellation of exactly one res
      # (§6.1), so the relation is keyed here rather than on the res.
      #
      # Deletion does not cascade. §14 routes removal through a recycle bin, and
      # a foreign key that quietly deletes names alongside the thing they name
      # would bypass it without reporting anything.
      add :res_id, references(:res, type: :uuid, on_delete: :nothing), null: false

      # §7.3: null denotes the household's shared vocabulary, which is the
      # unmarked default. A value marks a name specific to one agent.
      add :assigner_id, references(:res, type: :uuid, on_delete: :nothing)

      add :nomen_string, :text, null: false
      add :scheme, :text
      # §7.2: null means genuinely absent, not unknown. Nothing may infer it.
      add :language, :text
      add :script, :text
      add :context_of_use, :text
      add :reference_source, :text
      add :intended_audience, :text
      add :script_conversion, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:nomens, [:res_id])
    create index(:nomens, [:assigner_id])

    # Deliberately not unique. §4.3 requires the catalog to tolerate the same
    # external identifier appearing on more than one entity, so this index
    # exists to find them, not to forbid the duplication.
    create index(:nomens, [:scheme, :nomen_string])
  end
end
