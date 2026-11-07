defmodule Pluteus.Repo.Migrations.KeySourcesAndPlaces do
  use Ecto.Migration

  # spec-05 §3.1: a source is a collective agent and is recorded as one, and a name it
  # supplies is a nomen it assigned. One agent per source, found again by the name the
  # registry gives the source.
  #
  # §9.7: a place a gazetteer names is one res however many photographs were taken in it,
  # found again by the gazetteer's identifier for it.
  def change do
    create table(:source_agents, primary_key: false) do
      add :source, :text, primary_key: true
      add :agent_id, references(:res, type: :uuid, on_delete: :nothing), null: false
    end

    create unique_index(:source_agents, [:agent_id])

    create table(:place_keys, primary_key: false) do
      add :geonameid, :integer, primary_key: true
      add :place_id, references(:res, type: :uuid, on_delete: :nothing), null: false
    end

    create unique_index(:place_keys, [:place_id])
  end
end
