defmodule Pluteus.Corpus.GazetteerTest do
  @moduledoc """
  A coordinate is answered from the gazetteer the household holds (spec-05 §9.7,
  criterion 31): nearest first, only by places someone can stand in today, and only as
  far as the registry says anything is worth saying.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Corpus.Gazetteer
  alias Pluteus.Corpus.Repo, as: CorpusRepo
  alias Pluteus.Matching.Registry

  @thresholds Registry.reverse_geocoding!("geonames")

  defp place!(geonameid, name, {latitude, longitude}, {class, code}, admin1 \\ "MI") do
    CorpusRepo.query!(
      """
      INSERT INTO geonames.places
        (geonameid, name, latitude, longitude, feature_class, feature_code, country_code, admin1_code)
      VALUES ($1, $2, $3, $4, $5, $6, 'US', $7)
      """,
      [geonameid, name, latitude, longitude, class, code, admin1]
    )
  end

  setup do
    place!(1, "Grand Rapids", {42.96336, -85.66809}, {"P", "PPLA2"})
    place!(2, "Walker", {42.99836, -85.76809}, {"P", "PPL"})
    # Nearer than either, and not a place anyone stands in today.
    place!(3, "Old Grand Rapids Quarter", {42.9640, -85.6690}, {"P", "PPLH"})
    place!(4, "Downtown", {42.9635, -85.6682}, {"P", "PPLX"})
    # Nearer still, and not a populated place at all.
    place!(5, "Grand River", {42.9634, -85.6681}, {"H", "STM"})
    place!(6, "Chicago", {41.85003, -87.65005}, {"P", "PPLA2"}, "IL")

    CorpusRepo.query!(
      "INSERT INTO geonames.admin1 (code, name, geonameid) VALUES ('US.MI', 'Michigan', 5001836)"
    )

    CorpusRepo.query!(
      "INSERT INTO geonames.countries (iso, name, geonameid) VALUES ('US', 'United States', 6252001)"
    )

    :ok
  end

  describe "31. A coordinate is answered by the places near it, from the copy held" do
    test "nearest first, with each one's distance" do
      assert [first, second] = Gazetteer.nearest(42.9634, -85.6681, @thresholds)
      assert {first.geonameid, first.name} == {1, "Grand Rapids"}
      assert second.geonameid == 2
      assert first.metres < 100 and second.metres > first.metres
      assert first.admin1_code == "MI"
    end

    test "only by a place someone can stand in today" do
      ids = 42.9634 |> Gazetteer.nearest(-85.6681, @thresholds) |> Enum.map(& &1.geonameid)

      refute 3 in ids, "a historical place answered"
      refute 4 in ids, "a section of a place answered"
      refute 5 in ids, "a river answered"
    end

    test "nothing further than the registry says is worth saying" do
      # Chicago is some 250 km from Grand Rapids.
      ids = 42.9634 |> Gazetteer.nearest(-85.6681, @thresholds) |> Enum.map(& &1.geonameid)
      refute 6 in ids

      assert Gazetteer.nearest(0.0, 0.0, @thresholds) == []
    end
  end

  describe "a division and a country are named by the publisher's own files" do
    test "by their codes" do
      assert Gazetteer.region("US", "MI") == %{geonameid: 5_001_836, name: "Michigan"}
      assert Gazetteer.country("US") == %{geonameid: 6_252_001, name: "United States"}
    end

    test "a code the files do not hold names nothing" do
      assert Gazetteer.region("US", "ZZ") == nil
      assert Gazetteer.country("ZZ") == nil
    end
  end
end
