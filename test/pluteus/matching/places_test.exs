defmodule Pluteus.Matching.PlacesTest do
  @moduledoc """
  A gazetteer's answer is recorded at the granularity the evidence supports, and a finer
  place is a candidate (spec-05 §9.7, criterion 39).
  """

  use ExUnit.Case, async: true

  alias Pluteus.Matching.Places
  alias Pluteus.Matching.Registry

  @thresholds Registry.reverse_geocoding!("geonames")

  defp place(geonameid, metres, country \\ "US", admin1 \\ "MI") do
    %{
      geonameid: geonameid,
      name: "place #{geonameid}",
      feature_code: "PPL",
      country_code: country,
      admin1_code: admin1,
      metres: metres
    }
  end

  defp at(accuracy), do: %{latitude: 42.96, longitude: -85.67, accuracy: accuracy}

  describe "39. A locality is recorded only where the evidence supports one" do
    test "a stated accuracy within the bound and a place near enough record that place" do
      nearest = place(1, 400.0)

      assert Places.answer(at(5.0), [nearest, place(2, 3_000.0)], @thresholds) ==
               %{recorded: {:locality, nearest}, candidate: nil}
    end

    test "with no stated accuracy, the region is recorded and the locality raised" do
      nearest = place(1, 400.0)
      neighbours = [nearest | Enum.map(2..5, &place(&1, 1_000.0 * &1))]

      assert Places.answer(at(nil), neighbours, @thresholds) ==
               %{
                 recorded: {:region, %{country_code: "US", admin1_code: "MI"}},
                 candidate: {:locality, nearest}
               }
    end

    test "an accuracy coarser than the bound is no better than none" do
      nearest = place(1, 400.0)

      assert %{recorded: {:region, _}, candidate: {:locality, ^nearest}} =
               Places.answer(at(250.0), [nearest, place(2, 900.0)], @thresholds)
    end

    test "however accurate the coordinate, a place too far away is not where it was taken" do
      # Precise, but the nearest settlement is twelve kilometres off: the photograph was
      # taken near it, not in it, and the locality is not raised either.
      assert Places.answer(at(3.0), [place(1, 12_000.0), place(2, 14_000.0)], @thresholds) ==
               %{recorded: {:region, %{country_code: "US", admin1_code: "MI"}}, candidate: nil}
    end
  end

  describe "39. Near a border, the coarser place the neighbours share is recorded" do
    test "neighbours in two divisions of one country record the country" do
      nearest = place(1, 2_000.0, "US", "MI")
      neighbours = [nearest, place(2, 3_000.0, "US", "IN"), place(3, 4_000.0, "US", "MI")]

      assert Places.answer(at(nil), neighbours, @thresholds) ==
               %{
                 recorded: {:country, %{country_code: "US"}},
                 candidate: {:region, %{country_code: "US", admin1_code: "MI"}}
               }
    end

    test "neighbours in two countries record nothing, and raise the nearest's country" do
      neighbours = [place(1, 2_000.0, "US", "MI"), place(2, 3_000.0, "CA", "08")]

      assert Places.answer(at(nil), neighbours, @thresholds) ==
               %{recorded: nil, candidate: {:country, %{country_code: "US"}}}
    end

    test "a place carrying no division cannot agree on one" do
      neighbours = [place(1, 2_000.0, "US", nil), place(2, 3_000.0, "US", nil)]

      assert %{recorded: {:country, _}, candidate: nil} =
               Places.answer(at(nil), neighbours, @thresholds)
    end
  end

  describe "§11. With nothing near enough, nothing is said" do
    test "no neighbours record nothing and raise nothing" do
      assert Places.answer(at(1.0), [], @thresholds) == %{recorded: nil, candidate: nil}
    end
  end
end
