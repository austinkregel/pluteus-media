defmodule Pluteus.Corpus.Repo.Migrations.HoldTheGeonamesGazetteer do
  use Ecto.Migration

  # spec-05 §9.7: a photograph's coordinate is answered from GeoNames held locally, and
  # criterion 31 forbids the query leaving the house. These are the publisher's own tables
  # as its readme lays them out, column for column, so that what is held is the dump and
  # not a reading of it.
  #
  # An import loads a staging schema of the same shape and exchanges the two in one
  # transaction with marking the snapshot imported, so a lookup reads one whole snapshot or
  # the other (§5.7). These tables are therefore the snapshot in use and nothing else.
  def up do
    # cube carries the distance operator and its GiST support; earthdistance places a
    # latitude and longitude on the earth as a cube. No PostGIS is needed for the nearest
    # point to a point.
    execute "CREATE EXTENSION IF NOT EXISTS cube"
    execute "CREATE EXTENSION IF NOT EXISTS earthdistance"

    execute "CREATE SCHEMA geonames"

    create table(:places, prefix: "geonames", primary_key: false) do
      add :geonameid, :integer, primary_key: true
      add :name, :text, null: false
      add :asciiname, :text
      add :alternatenames, :text
      add :latitude, :float, null: false
      add :longitude, :float, null: false
      add :feature_class, :text
      add :feature_code, :text
      add :country_code, :text
      add :cc2, :text
      add :admin1_code, :text
      add :admin2_code, :text
      add :admin3_code, :text
      add :admin4_code, :text
      add :population, :bigint
      add :elevation, :integer
      add :dem, :integer
      add :timezone, :text
      add :modified_on, :date
    end

    # Only a populated place answers a coordinate as a locality, so only those are indexed
    # by position. `<->` between two earth points orders by chord length, which orders as
    # the distance over the surface does.
    execute """
    CREATE INDEX places_populated_by_position ON geonames.places
      USING gist (ll_to_earth(latitude, longitude))
      WHERE feature_class = 'P'
    """

    # The publisher's names for first- and second-order divisions, keyed by the codes a
    # place's admin columns carry: `US.MI` and `US.MI.081`.
    create table(:admin1, prefix: "geonames", primary_key: false) do
      add :code, :text, primary_key: true
      add :name, :text, null: false
      add :asciiname, :text
      add :geonameid, :integer, null: false
    end

    create table(:admin2, prefix: "geonames", primary_key: false) do
      add :code, :text, primary_key: true
      add :name, :text, null: false
      add :asciiname, :text
      add :geonameid, :integer, null: false
    end
  end

  def down do
    execute "DROP SCHEMA geonames CASCADE"
    execute "DROP EXTENSION earthdistance"
    execute "DROP EXTENSION cube"
  end
end
