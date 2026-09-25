defmodule Pluteus.Catalog.ResolutionTest do
  @moduledoc """
  spec-10 §6.1's language step: [IIIF-PRES] §4.4's selection adopted as a filter
  that narrows the candidate set, after which spec-01 §7.4's ordering chooses
  within it.

  Criterion 10 asks that the four clauses be followed in order and that clause 3
  apply only where every candidate carries a language. Criterion 11 asks that
  resolution stay deterministic, including where clause 3 applies.

  `choose/2` is pure, so the clauses are exercised over nomens built here rather
  than through the database. The ordering it defers to is asserted over fixtures
  in `Pluteus.Catalog.NamingTest`.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Resolution

  defp nomen(string, attrs \\ []) do
    %Nomen{
      id: UUIDv7.generate(),
      nomen_string: string,
      language: attrs[:language],
      assigner_id: attrs[:assigner_id],
      provenance: attrs[:provenance] || :local
    }
  end

  describe "10. Resolution's language step follows §6.1's four clauses in order" do
    test "clause 1: where every candidate has no language, all are candidates" do
      household = nomen("Amma", provenance: :automatic)
      personal = nomen("Amma-ji", assigner_id: UUIDv7.generate())

      chosen = Resolution.choose([household, personal], %Profile{language: "en"})

      assert chosen.nomen_string == "Amma-ji"
    end

    test "clause 2: where some candidates match the profile's language, only those are" do
      english = nomen("Symphony", language: "en", provenance: :automatic)
      german = nomen("Sinfonie", language: "de")
      untagged = nomen("Symphonie")

      chosen = Resolution.choose([english, german, untagged], %Profile{language: "en"})

      assert chosen.nomen_string == "Symphony"
    end

    test "clause 3: where all carry a language and none matches, candidates are of one language" do
      italian = nomen("1 marzo 2015", language: "it")
      hebrew = nomen("10 Adar 5775", language: "he", provenance: :seeded)

      chosen = Resolution.choose([italian, hebrew], %Profile{language: "ja"})

      # The ordering selects among the tagged names, and its choice fixes the
      # language; :local outranks :seeded, so Italian is the language and the
      # Italian name is the answer.
      assert chosen.nomen_string == "1 marzo 2015"
    end

    test "clause 4: where only some carry a language and none matches, candidates carry none" do
      italian = nomen("Nazioni Unite", language: "it")
      untagged = nomen("UN", provenance: :automatic)

      chosen = Resolution.choose([italian, untagged], %Profile{language: "ja"})

      assert chosen.nomen_string == "UN"
    end

    test "clause 3 does not swallow clause 4" do
      # §6.1 requires the word *all* in clause 3 for exactly this shape: without
      # it, a seeded name in a language nobody asked for displaces the
      # household's own untagged one, which §7.2 leaves deliberately untagged.
      household = nomen("Amma", provenance: :automatic)
      seeded = nomen("grand-mère", language: "fr", provenance: :seeded)

      chosen = Resolution.choose([household, seeded], %Profile{language: "en"})

      assert chosen.nomen_string == "Amma"
    end
  end

  describe "a range matches a tag by [RFC4647] §3.3.1 basic filtering" do
    test "a tag matches the range it equals and the range it extends" do
      assert Resolution.matches?("en", "en")
      assert Resolution.matches?("en-GB", "en")
      assert Resolution.matches?("en-Latn-GB", "en")
      assert Resolution.matches?("en-GB-oxendict", "en-GB")
    end

    test "a range is never satisfied by a tag less specific than itself" do
      refute Resolution.matches?("en", "en-GB")
      refute Resolution.matches?("en-Latn", "en-Latn-GB")
    end

    test "a subtag boundary is required, so one tag is not a prefix of another by letters" do
      refute Resolution.matches?("english", "en")
      refute Resolution.matches?("enm", "en")
    end

    test "case is ignored, since [RFC5646] §2.1 makes a tag case-insensitive" do
      assert Resolution.matches?("EN-gb", "en-GB")
      assert Resolution.matches?("en-latn-gb", "EN")
    end

    test "an untagged nomen is untagged under every range" do
      refute Resolution.matches?(nil, "en")
      refute Resolution.matches?("en", nil)
    end

    test "clause 2 takes a regional variant where the profile asks for the language" do
      british = nomen("Colour Chart", language: "en-GB", provenance: :automatic)
      german = nomen("Farbtafel", language: "de")

      chosen = Resolution.choose([british, german], %Profile{language: "en"})

      assert chosen.nomen_string == "Colour Chart"
    end

    test "a profile asking for a variant does not take the bare language through clause 2" do
      # `en` does not match the range `en-GB`, so clause 2 finds nothing, and
      # clause 4 answers with the untagged name rather than the English one.
      english = nomen("Color Chart", language: "en", provenance: :automatic)
      untagged = nomen("The Chart")

      chosen = Resolution.choose([english, untagged], %Profile{language: "en-GB"})

      assert chosen.nomen_string == "The Chart"
    end

    test "where every candidate is tagged, a variant request falls to clause 3" do
      english = nomen("Color Chart", language: "en", provenance: :automatic)
      german = nomen("Farbtafel", language: "de")

      chosen = Resolution.choose([english, german], %Profile{language: "en-GB"})

      # Clause 3 picks the language of the nomen the ordering would select. Both
      # are household names, so provenance decides: :local outranks :automatic.
      assert chosen.nomen_string == "Farbtafel"
    end
  end

  describe "11. Resolution of one res and profile returns the same nomen across calls" do
    test "clause 3 answers alike however the candidates arrive" do
      nomens = [
        nomen("1 marzo 2015", language: "it"),
        nomen("10 Adar 5775", language: "he", provenance: :seeded),
        nomen("1 March 2015", language: "en", provenance: :seeded)
      ]

      profile = %Profile{language: "ja"}
      expected = Resolution.choose(nomens, profile).id

      for permutation <- permutations(nomens) do
        assert Resolution.choose(permutation, profile).id == expected
      end
    end

    test "clause 3 answers alike across calls" do
      nomens = [
        nomen("1 marzo 2015", language: "it"),
        nomen("10 Adar 5775", language: "he")
      ]

      profile = %Profile{language: "ja"}

      assert Resolution.choose(nomens, profile).id == Resolution.choose(nomens, profile).id
    end
  end

  describe "§6.1 inverts §7.4's precedence, deliberately" do
    test "a personal name in a language the person cannot read loses to a household one" do
      # §7.4's ordering puts a personal nomen first and treats language as a
      # later tiebreak. Under the filter, language narrows first: clause 2 keeps
      # only the English names, and the personal German one is not among them.
      personal_german = nomen("Sinfonie", language: "de", assigner_id: UUIDv7.generate())
      household_english = nomen("Symphony", language: "en", provenance: :automatic)

      chosen =
        Resolution.choose([personal_german, household_english], %Profile{language: "en"})

      assert chosen.nomen_string == "Symphony"
    end
  end

  describe "a profile naming no language narrows nothing" do
    test "a nil language does not ask for names that are themselves untagged" do
      # Filtering to the untagged names here would discard the personal name
      # before §7.4's ordering ever saw it, and the person would be shown the
      # household's word for their own grandmother.
      household = nomen("Amma", provenance: :automatic)
      personal = nomen("Oma", language: "de", assigner_id: UUIDv7.generate())

      chosen = Resolution.choose([household, personal], %Profile{})

      assert chosen.nomen_string == "Oma"
    end

    test "a res whose every name carries a language still resolves under a nil profile" do
      {:ok, res} = Catalog.create_res(%{kind: :person})
      nomen!(res.id, %{nomen_string: "Nazioni Unite", language: "it"})
      nomen!(res.id, %{nomen_string: "United Nations", language: "en"})

      assert %Nomen{} = Resolution.resolve(res.id, %Profile{})
    end
  end

  defp nomen!(res_id, attrs) do
    Pluteus.CatalogFixtures.nomen!(res_id, attrs)
  end

  defp permutations([]), do: [[]]

  defp permutations(list) do
    for element <- list, rest <- permutations(list -- [element]), do: [element | rest]
  end
end
