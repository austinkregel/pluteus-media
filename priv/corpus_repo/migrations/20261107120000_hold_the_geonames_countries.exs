defmodule Pluteus.Corpus.Repo.Migrations.HoldTheGeonamesCountries do
  use Ecto.Migration

  # The publisher's countryInfo, column for column. It is the one place GeoNames names
  # every country a place's country code can stand for, with that country's geonameid:
  # the gazetteer's own country rows miss territories such as American Samoa and Aruba,
  # which countryInfo lists.
  def change do
    create table(:countries, prefix: "geonames", primary_key: false) do
      add :iso, :text, primary_key: true
      add :iso3, :text
      add :iso_numeric, :text
      add :fips, :text
      add :name, :text, null: false
      add :capital, :text
      add :area_square_km, :float
      add :population, :bigint
      add :continent, :text
      add :tld, :text
      add :currency_code, :text
      add :currency_name, :text
      add :phone, :text
      add :postal_code_format, :text
      add :postal_code_regex, :text
      add :languages, :text
      add :geonameid, :integer, null: false
      add :neighbours, :text
      add :equivalent_fips_code, :text
    end
  end
end
