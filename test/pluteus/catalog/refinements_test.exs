defmodule Pluteus.Catalog.RefinementsTest do
  @moduledoc """
  spec-01 §6.3: LRM-R33 and LRM-R35 MUST be refined, and the registry carries the
  refinements a document in this series cites and no others.

  The second half of that sentence is the part worth testing. A registry of relations
  nobody writes is the failure §6.3 names outright — "a refinement nothing writes is a
  row that only looks like coverage" — so a test that only checked the cited ones were
  present would pass just as happily over a registry that had grown every candidate LRM
  mentions.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Association
  alias Pluteus.Catalog.Refinements
  alias Pluteus.Ingest.Place
  alias Pluteus.Ingest.Registry

  # Every refinement a document in this series cites, with the relation its citation
  # refines. Written out rather than read from the module, so this is a second statement
  # of the vocabulary and not the same list checked against itself.
  #
  # spec-01 §6.3 and §7.5 account for six. spec-04 cites seven more, all refining LRM-R1:
  # §4.6 makes each companion link "an association refining LRM-R1 whose type names the
  # relation", and §6.4 links a track's extent within a single-file release to its track
  # manifestation the same way.
  @cited [
    {"time-of-capture", "LRM-R35"},
    {"time-of-publication-or-manufacture", "LRM-R35"},
    {"place-of-capture", "LRM-R33"},
    {"place-within-place", "LRM-R1"},
    {"arrangement-position-of-source-numbering", "LRM-R1"},
    {"same-thing", "LRM-R1"},
    {"extent-of", "LRM-R1"},
    {"cover-art-of", "LRM-R1"},
    {"lyrics-of", "LRM-R1"},
    {"subtitles-of", "LRM-R1"},
    {"cue-sheet-of", "LRM-R1"},
    {"description-of", "LRM-R1"},
    {"metadata-of", "LRM-R1"}
  ]

  describe "§6.3. The registry carries what the series cites, and no others" do
    test "every cited refinement is shipped, and nothing else is" do
      assert Enum.sort(Refinements.names()) == Enum.sort(Enum.map(@cited, &elem(&1, 0)))
    end

    test "each refines the relation its citation refines" do
      for {name, relation} <- @cited do
        assert Refinements.relation(name) == relation
      end
    end

    test "none of LRM's further candidates is carried" do
      # §6.3 lists these and declines every one: "None is carried until something writes
      # it." They are the set most likely to be added for completeness, which is the
      # thing the section forbids.
      for candidate <- ~w(
            time-of-work-conception
            time-of-work-creation
            time-of-expression-creation
            period-of-ownership
            date-of-birth
            time-of-validity
          ) do
        refute Refinements.known?(candidate)
      end
    end

    test "each names the document that cites it, so a release can tell why it is here" do
      for refinement <- Refinements.all() do
        assert is_binary(refinement["cited_by"])
        assert refinement["cited_by"] =~ "spec-"
      end
    end

    test "each refines one of the three relations §6.3 declares" do
      for refinement <- Refinements.all() do
        assert refinement["relation"] in ~w(LRM-R33 LRM-R35 LRM-R1)
      end
    end

    test "both relations §6.3 makes a MUST have at least one refinement" do
      # The MUST is on refining them. A relation with an entry in the table and none in
      # the registry would be the obligation stated and unmet.
      assert Refinements.of_relation("LRM-R33") != []
      assert Refinements.of_relation("LRM-R35") != []
    end
  end

  describe "§6.3. A relation is never written without one" do
    test "an unshipped refinement raises rather than being recorded" do
      # §6.3: "A relation written before its refinement existed is untyped, and stays
      # untyped. Nothing recorded which kind it would have been, so nothing can classify
      # it afterwards." So the row is not one to repair later — its meaning is already
      # gone, which is why this refuses instead of writing.
      %{local: subject, seeded: object} = two_res()

      assert_raise ArgumentError, ~r/not an association refinement this release ships/, fn ->
        Catalog.associate(subject.id, object.id, "time-of-work-conception")
      end
    end

    test "the refusal names what exists, so the caller is not left guessing" do
      %{local: subject, seeded: object} = two_res()

      message =
        assert_raise ArgumentError, fn ->
          Catalog.associate(subject.id, object.id, "invented")
        end

      for name <- Refinements.names(), do: assert(message.message =~ name)
    end

    test "a shipped refinement is recorded" do
      %{local: subject, seeded: object} = two_res()

      assert {:ok, _association} =
               Catalog.associate(subject.id, object.id, "time-of-publication-or-manufacture")
    end
  end

  describe "spec-04 §4.6. Every companion kind has the refinement its link needs" do
    test "each kind the ingest registry names resolves to a shipped refinement" do
      # A companion's link is an association refining LRM-R1 "whose type names the
      # relation", so the two registries have to agree: a companion kind added without
      # its refinement would place the companion and then refuse the link, part way
      # through placing the file.
      for kind <- Registry.companion_kinds() do
        assert Refinements.known?(Place.companion_link(kind))
      end
    end

    test "a kind no refinement is shipped for raises rather than writing an untyped link" do
      assert_raise ArgumentError, fn -> Place.companion_link("sheet_music") end
    end
  end

  describe "§17. The vocabulary lives in one place" do
    test "the same-thing link resolves through the registry" do
      # §17 makes the refinements seed data, so the string a release may rename lives in
      # the file rather than in a module beside it.
      assert Association.same_thing() == "same-thing"
      assert Refinements.known?(Association.same_thing())
    end

    test "naming a refinement the registry has lost raises" do
      assert_raise ArgumentError, fn -> Refinements.name!("same-think") end
    end
  end

  defp two_res do
    {:ok, local} = Catalog.create_res(%{kind: :place})
    {:ok, seeded} = Catalog.create_res(%{kind: :place})

    %{local: local, seeded: seeded}
  end
end
