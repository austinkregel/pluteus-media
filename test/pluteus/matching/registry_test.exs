defmodule Pluteus.Matching.RegistryTest do
  @moduledoc """
  spec-05 §15's registries hold together: every scheme names a level §4.1 knows, every
  corpus answers only schemes the registry holds, and the rank order starts where §5.3
  says it must.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Matching.Registry
  alias Pluteus.Surfaces.Registry, as: Surfaces

  describe "§4.1. A scheme identifies a level" do
    test "every scheme names a level the registry knows" do
      for scheme <- Registry.schemes() do
        assert Registry.level(scheme) in Registry.levels(),
               "#{scheme} names #{Registry.level(scheme)}, which is no level"
      end
    end

    test "several identifiers of one scheme at one level are ordinary for an ISRC alone" do
      # §5.4: distributors assign their own ISRCs to one recording. Every other scheme's
      # second identifier at one level is a contradiction.
      assert Enum.filter(Registry.schemes(), &Registry.several?/1) == ["isrc"]
    end

    test "a check digit is named only where §4.4 gives one" do
      assert Registry.check("isbn") == "isbn"
      assert Registry.check("iswc") == "mod10"
      assert Registry.check("musicbrainz_recording") == nil
    end

    test "a writer naming a scheme the registry does not hold raises" do
      assert Registry.scheme!("musicbrainz_artist") == "musicbrainz_artist"
      assert_raise KeyError, fn -> Registry.scheme!("musicbrainz") end
    end
  end

  describe "§5.5, §5.7. A corpus answers registered schemes, and says how it arrives" do
    test "every scheme a corpus answers is one the registry holds" do
      for corpus <- Registry.corpora(), scheme <- Registry.answers(corpus) do
        assert scheme in Registry.schemes(), "#{corpus} answers #{scheme}, which is unknown"
      end
    end

    test "every corpus is fetched, replicated or dropped, and states its terms" do
      for corpus <- Registry.corpora() do
        assert Registry.acquisition(corpus) in [:fetched, :replicated, :dropped]
        assert Registry.terms(corpus) != ""
        assert is_boolean(Registry.advances?(corpus))
      end
    end

    test "what admits a person and not a program is dropped" do
      for corpus <- ~w(grand_comics_database no_intro redump) do
        assert Registry.acquisition(corpus) == :dropped
      end
    end

    test "GeoNames is fetched from its dump directory and verified by size alone" do
      # The publisher states no checksum, so §5.7 leaves the announced size as the check.
      assert %{
               from: "https://download.geonames.org/export/dump/",
               files: ["allCountries.zip", "admin1CodesASCII.txt", "admin2Codes.txt"],
               verified_by: :size,
               stated_by: :last_modified
             } = Registry.fetch!("geonames")
    end

    test "a corpus whose entry names no address cannot be fetched" do
      assert_raise KeyError, fn -> Registry.fetch!("discogs") end
    end
  end

  describe "§5.3. A member's assertion ranks first" do
    test "and the rest follow in the specification's order" do
      assert Registry.rank_order() == ~w(member companion embedded_tags corpus provider)
    end
  end

  describe "one list of schemes" do
    test "the interface's schemes are its own and spec-05's, listed once" do
      assert Surfaces.nomen_schemes() == ["ordering" | Registry.schemes()]
    end
  end
end
