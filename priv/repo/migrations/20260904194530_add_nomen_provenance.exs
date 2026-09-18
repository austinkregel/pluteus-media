defmodule Pluteus.Repo.Migrations.AddNomenProvenance do
  use Ecto.Migration

  # §7.5 separates shipped data from what the household adds, and the separation
  # has to be recorded per row: an upgrade replaces the entire seed set, and
  # anything not marked as shipped must survive that untouched.
  #
  # `automatic` is the third case §7.5 names — a name obtained by matching
  # against an external source. It ranks below a person's correction so that
  # re-running a match cannot overwrite one.
  @provenances ~w(seeded automatic local)

  def change do
    alter table(:nomens) do
      add :provenance, :string, null: false, default: "local"
    end

    create constraint(:nomens, :provenance_must_be_known,
             check: "provenance IN (#{Enum.map_join(@provenances, ", ", &"'#{&1}'")})"
           )

    create index(:nomens, [:provenance])
  end
end
