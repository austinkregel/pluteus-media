defmodule Pluteus.Corpus.Gazetteer do
  @moduledoc """
  Answers a coordinate from the GeoNames snapshot the household holds (spec-05 §9.7).

  **Nothing leaves the house** (criterion 31). Every answer is read from the corpora's own
  database, and a coordinate is the sharpest disclosure there is (§14): where a member of
  the household stood.

  The answer is the nearest populated places and how far each is, which is a resemblance
  (§9.7). What it supports is decided by `Pluteus.Matching.Places`; this module only reads.
  """

  alias Pluteus.Corpus.Repo

  @typedoc "A populated place near a coordinate, and its distance from it in metres."
  @type neighbour :: %{
          geonameid: pos_integer(),
          name: String.t(),
          feature_code: String.t(),
          country_code: String.t() | nil,
          admin1_code: String.t() | nil,
          metres: float()
        }

  @typedoc "A place the gazetteer names: a country or a first-order division."
  @type named :: %{geonameid: pos_integer(), name: String.t()}

  @doc """
  The nearest places answering a coordinate, nearest first: at most `count`, none further
  than `within` metres, and only those whose feature code is among `codes`.

  The position index holds every populated place, so the codes are a filter on its scan
  rather than a part of the index: a change to which codes answer needs no migration.
  """
  @spec nearest(float(), float(), %{
          answering_codes: [String.t()],
          agreeing_places: pos_integer(),
          nearby_within_metres: number()
        }) :: [neighbour()]
  def nearest(latitude, longitude, %{
        answering_codes: codes,
        agreeing_places: count,
        nearby_within_metres: within
      }) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT geonameid, name, feature_code, country_code, admin1_code,
               earth_distance(ll_to_earth(latitude, longitude), ll_to_earth($1, $2))
        FROM geonames.places
        WHERE feature_class = 'P' AND feature_code = ANY($3)
        ORDER BY ll_to_earth(latitude, longitude) <-> ll_to_earth($1, $2)
        LIMIT $4
        """,
        [latitude, longitude, codes, count]
      )

    rows
    |> Enum.map(fn [geonameid, name, code, country, admin1, metres] ->
      %{
        geonameid: geonameid,
        name: name,
        feature_code: code,
        country_code: country,
        admin1_code: admin1,
        metres: metres
      }
    end)
    |> Enum.take_while(&(&1.metres <= within))
  end

  @doc """
  The first-order division a country code and an admin1 code name, as the publisher's code
  file names it, or nil where the file holds no such code.
  """
  @spec region(String.t(), String.t()) :: named() | nil
  def region(country_code, admin1_code) do
    one("SELECT geonameid, name FROM geonames.admin1 WHERE code = $1", [
      country_code <> "." <> admin1_code
    ])
  end

  @doc """
  The country a country code names, as the publisher's country file names it, or nil
  where the file holds no such code.
  """
  @spec country(String.t()) :: named() | nil
  def country(country_code) do
    one("SELECT geonameid, name FROM geonames.countries WHERE iso = $1", [country_code])
  end

  defp one(sql, parameters) do
    case Repo.query!(sql, parameters).rows do
      [] -> nil
      [[geonameid, name]] -> %{geonameid: geonameid, name: name}
    end
  end
end
