defmodule Pluteus.Catalog.ConformanceTest do
  @moduledoc """
  Behavioural conformance with spec-01 §15.

  Each `describe` block states one numbered criterion verbatim. A failure here
  means the implementation has stopped conforming, not that a test needs
  adjusting.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Assets
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.Addressing
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.AssetRole
  alias Pluteus.Catalog.Association
  alias Pluteus.Catalog.DeepLink
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Item
  alias Pluteus.Catalog.Manifestation
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Res
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Catalog.Seeds
  alias Pluteus.Catalog.Work
  alias Pluteus.CatalogFixtures
  alias Pluteus.Events
  alias Pluteus.Events.Event
  alias Pluteus.Events.ResumePosition
  alias Pluteus.Lifecycle
  alias Pluteus.Lifecycle.Tombstone
  alias Pluteus.Principals
  alias Pluteus.Principals.Identity
  alias Pluteus.Principals.Principal
  alias Pluteus.Storage
  alias Pluteus.StorageFixtures

  describe "1. Every entity returns a UUIDv7 primary identifier" do
    test "for a res of every kind the model defines" do
      for kind <- Res.kinds() do
        {:ok, res} = Catalog.create_res(%{kind: kind})

        assert uuidv7?(res.id), "kind #{kind} produced #{res.id}, which is not a UUIDv7"
      end
    end

    test "for a nomen, whose identifier comes from its own res row" do
      {:ok, work} = Catalog.create_res(%{kind: :work})
      {:ok, nomen} = Catalog.create_nomen(%{res_id: work.id, nomen_string: "Odyssey"})

      assert uuidv7?(nomen.id)
      assert %Res{kind: :nomen} = Catalog.get_res(nomen.id)
    end

    test "with a timestamp that places it in the present" do
      {:ok, res} = Catalog.create_res(%{kind: :work})

      minted_at = UUIDv7.timestamp(res.id)
      now = System.system_time(:millisecond)

      assert_in_delta minted_at, now, 60_000
    end
  end

  describe "2. Seeded entities carry identical identifiers across two installs" do
    test "a second load of the same release reproduces the first load's identifiers" do
      :ok = Seeds.load(seed_fixture_dir())
      first = seeded_ids()

      Repo.delete_all(Nomen)
      Repo.delete_all(Res)

      :ok = Seeds.load(seed_fixture_dir())
      second = seeded_ids()

      assert first == second
      refute first == []
    end

    test "the loader inserts the identifiers it is given rather than minting them" do
      :ok = Seeds.load(seed_fixture_dir())

      assert Catalog.get_res("01a06ddf-9f40-793c-9b87-6af90e5df151")
      assert Catalog.get_nomen("01a06ddf-9f43-7e2f-896a-3ec229bd334d")
    end

    test "an entry with no identifier is refused rather than filled in" do
      dir = tmp_seed_dir(~s([{"kind": "place"}]))

      assert_raise Seeds.Error, fn -> Seeds.load(dir) end
    end

    test "a nomen with no identifier is refused rather than filled in" do
      dir =
        tmp_seed_dir("""
        [{"id": "01a06ddf-9f40-793c-9b87-6af90e5df151", "kind": "place",
          "nomens": [{"nomen_string": "unnamed"}]}]
        """)

      assert_raise Seeds.Error, fn -> Seeds.load(dir) end
    end
  end

  describe "3. An entity with zero external identifiers is fully functional" do
    test "it can be created, retrieved, and named" do
      {:ok, work} = Catalog.create_res(%{kind: :work})

      {:ok, nomen} =
        Catalog.create_nomen(%{res_id: work.id, nomen_string: "Anatomy of the human body"})

      assert %Res{kind: :work} = Catalog.get_res(work.id)
      assert [%Nomen{nomen_string: "Anatomy of the human body"}] = Catalog.nomens_for(work.id)
      assert is_nil(nomen.scheme)
    end

    test "carrying a name in no scheme is not an absent external identifier" do
      {:ok, work} = Catalog.create_res(%{kind: :work})
      {:ok, _nomen} = Catalog.create_nomen(%{res_id: work.id, nomen_string: "978-0-00-000000-0"})

      assert Catalog.nomens_by_external_identifier("isbn", "978-0-00-000000-0") == []
    end
  end

  describe "4. Two entities may carry the same external identifier without error" do
    test "both inserts succeed and both are returned by lookup" do
      isbn = "978-0-375-50291-0"

      {:ok, first} = Catalog.create_res(%{kind: :manifestation})
      {:ok, second} = Catalog.create_res(%{kind: :manifestation})

      {:ok, _} =
        Catalog.create_nomen(%{res_id: first.id, nomen_string: isbn, scheme: "isbn"})

      {:ok, _} =
        Catalog.create_nomen(%{res_id: second.id, nomen_string: isbn, scheme: "isbn"})

      named = Catalog.nomens_by_external_identifier("isbn", isbn)

      assert [_, _] = named
      assert Enum.sort(Enum.map(named, & &1.res_id)) == Enum.sort([first.id, second.id])
    end

    test "one entity may carry the same identifier in two schemes" do
      value = "0000000121022127"
      {:ok, person} = Catalog.create_res(%{kind: :person})

      {:ok, _} = Catalog.create_nomen(%{res_id: person.id, nomen_string: value, scheme: "isni"})
      {:ok, _} = Catalog.create_nomen(%{res_id: person.id, nomen_string: value, scheme: "viaf"})

      assert [_, _] = Catalog.nomens_for(person.id)
    end
  end

  describe "5. An expression referencing two works is rejected" do
    test "the realized work is single-valued, so a second cannot be added" do
      {:ok, %{work: work, expression: expression}} = Catalog.create_work("Odyssey")

      realized =
        Repo.all(
          from w in Work,
            join: e in Expression,
            on: e.work_id == w.id,
            where: e.id == ^expression.id
        )

      assert [%Work{id: id}] = realized
      assert id == work.id
    end

    test "an expression realizing no work at all is rejected" do
      {:ok, res} = Catalog.create_res(%{kind: :expression})

      assert {:error, changeset} =
               %Expression{} |> Expression.changeset(%{id: res.id}) |> Repo.insert()

      assert %{work_id: [_ | _]} = errors_on(changeset)
    end
  end

  describe "6. An item referencing two manifestations is rejected" do
    test "the exemplified manifestation is single-valued" do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("Odyssey")
      {:ok, %{item: item}} = Catalog.create_item(manifestation.id, "Ada's copy")

      assert item.manifestation_id == manifestation.id
    end

    test "an item exemplifying no manifestation is rejected" do
      {:ok, res} = Catalog.create_res(%{kind: :item})

      assert {:error, changeset} = %Item{} |> Item.changeset(%{id: res.id}) |> Repo.insert()

      assert %{manifestation_id: [_ | _]} = errors_on(changeset)
    end
  end

  describe "7. A manifestation embodying several expressions is accepted" do
    test "a container carrying two parallel expressions" do
      {:ok, %{work: work, manifestation: manifestation}} = Catalog.create_work("Odyssey")
      {:ok, %{expression: second}} = Catalog.add_expression(work.id, "Odyssey, Italian dub")

      {:ok, _} = Catalog.embody(second.id, manifestation.id)

      assert [_, _] = Catalog.expressions_in(manifestation.id)
    end
  end

  describe "8. A work is created with an expression; its last may later be deleted" do
    test "a work created with no expression is refused at commit" do
      assert_raise Postgrex.Error, fn ->
        Repo.transaction(fn ->
          {:ok, res} = Catalog.create_res(%{kind: :work})
          {:ok, _work} = %Work{} |> Work.changeset(%{id: res.id}) |> Repo.insert()

          Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")
        end)
      end
    end

    test "a work created with an expression commits" do
      assert {:ok, %{work: %Work{}}} = Catalog.create_work("Odyssey")
      Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")
    end

    test "deleting a work's last expression leaves the work standing" do
      {:ok, %{work: work, expression: expression}} = Catalog.create_work("Odyssey")

      # Discharges the creation-time check before anything is removed. Without
      # it the sandbox would hold the creation and the deletion in one
      # transaction, and the obligation would be evaluated against a state that
      # never exists at any real commit.
      Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")

      Repo.delete_all(from e in Embodiment, where: e.expression_id == ^expression.id)
      {:ok, _} = Repo.delete(expression)

      assert Catalog.expressions_of(work.id) == []
      assert Repo.get(Work, work.id)
    end
  end

  describe "9. Whole-part between an aggregating work and an aggregated work is rejected" do
    test "refused when the aggregation is recorded first" do
      {:ok, %{work: anthology, expression: anthology_expression}} = Catalog.create_work("Odyssey")
      {:ok, %{work: story, expression: story_expression}} = Catalog.create_work("Odyssey")

      {:ok, _} = Catalog.aggregate(anthology_expression.id, story_expression.id)

      assert_raise Postgrex.Error, fn -> Catalog.add_work_part(anthology.id, story.id) end
    end

    test "refused when the whole-part relation is recorded first" do
      {:ok, %{work: whole, expression: whole_expression}} = Catalog.create_work("Odyssey")
      {:ok, %{work: part, expression: part_expression}} = Catalog.create_work("Odyssey")

      {:ok, _} = Catalog.add_work_part(whole.id, part.id)

      assert_raise Postgrex.Error, fn ->
        Catalog.aggregate(whole_expression.id, part_expression.id)
      end
    end

    test "a whole-part relation between works that do not aggregate is accepted" do
      {:ok, %{work: trilogy}} = Catalog.create_work("Odyssey")
      {:ok, %{work: volume}} = Catalog.create_work("Odyssey")

      assert {:ok, _} = Catalog.add_work_part(trilogy.id, volume.id)
    end
  end

  describe "10. A second scan produces a manifestation, not a duplicate work" do
    test "the existing expression gains a manifestation and the work is untouched" do
      {:ok, %{work: work, expression: expression, manifestation: first}} =
        Catalog.create_work("Odyssey")

      {:ok, %{manifestation: second}} =
        Catalog.add_manifestation(expression.id, "Odyssey, second scan")

      refute first.id == second.id
      assert [_, _] = Catalog.manifestations_of(expression.id)
      assert [%Expression{id: only}] = Catalog.expressions_of(work.id)
      assert only == expression.id
    end
  end

  describe "11. No title column exists on work, expression, manifestation, or item" do
    test "names reach the structural entities only through nomens" do
      for schema <- [Work, Expression, Manifestation, Item] do
        fields = schema.__schema__(:fields)

        refute :title in fields, "#{inspect(schema)} has a title column"
        refute :name in fields, "#{inspect(schema)} has a name column"
        refute :label in fields, "#{inspect(schema)} has a label column"
      end
    end
  end

  describe "12. A nomen with a null language round-trips and renders" do
    test "null survives the write and is not filled in on read" do
      {:ok, work} = an_unnamed_res()

      {:ok, nomen} =
        Catalog.create_nomen(%{res_id: work.id, nomen_string: "Amma", language: nil})

      assert is_nil(Catalog.get_nomen(nomen.id).language)
      assert Resolution.resolve(work.id, %Profile{}).nomen_string == "Amma"
    end

    test "a language preference does not exclude an untagged name" do
      {:ok, work} = an_unnamed_res()
      {:ok, _} = Catalog.create_nomen(%{res_id: work.id, nomen_string: "Amma", language: nil})

      assert Resolution.resolve(work.id, %Profile{language: "is"}).nomen_string == "Amma"
    end
  end

  describe "13. Resolution returns a nomen for every res" do
    test "including one carrying only a null-assigner name" do
      {:ok, work} = an_unnamed_res()
      {:ok, _} = Catalog.create_nomen(%{res_id: work.id, nomen_string: "Household name"})

      assert %Nomen{nomen_string: "Household name"} = Resolution.resolve(work.id, %Profile{})
    end

    test "a personal name outranks the household name for its own assigner" do
      {:ok, work} = an_unnamed_res()
      {:ok, reader} = Catalog.create_res(%{kind: :person})

      {:ok, _} = Catalog.create_nomen(%{res_id: work.id, nomen_string: "Household name"})

      {:ok, _} =
        Catalog.create_nomen(%{
          res_id: work.id,
          nomen_string: "What I call it",
          assigner_id: reader.id
        })

      assert Resolution.resolve(work.id, %Profile{assigner_id: reader.id}).nomen_string ==
               "What I call it"

      assert Resolution.resolve(work.id, %Profile{}).nomen_string == "Household name"
    end

    test "and resolution of a res exempt from LRM-R13 fails rather than inventing one" do
      %{expression: expression} = a_film()
      {:ok, %{address: address}} = Catalog.create_address(expression.id, a_cue())

      assert_raise Resolution.NoNomenError, fn -> Resolution.resolve(address.id, %Profile{}) end
    end
  end

  describe "14. Resolution twice with the same res and profile returns the same nomen" do
    test "when preferences leave several names tied" do
      {:ok, work} = one_work()

      for string <- ~w(Alpha Beta Gamma) do
        {:ok, _} = Catalog.create_nomen(%{res_id: work.id, nomen_string: string})
      end

      profile = %Profile{}
      first = Resolution.resolve(work.id, profile)

      for _ <- 1..5 do
        assert Resolution.resolve(work.id, profile).id == first.id
      end
    end

    test "the choice does not depend on the order the names arrive in" do
      {:ok, work} = one_work()

      # Every preference ties, so only the identifier separates them. A database
      # gives no ordering guarantee without ORDER BY, so the selection must not
      # inherit one.
      nomens =
        for string <- ~w(Alpha Beta Gamma Delta) do
          {:ok, nomen} = Catalog.create_nomen(%{res_id: work.id, nomen_string: string})
          nomen
        end

      profile = %Profile{}
      expected = Resolution.choose(nomens, profile)

      for permutation <- permutations(nomens) do
        assert Resolution.choose(permutation, profile).id == expected.id
      end
    end

    test "and resolution writes nothing" do
      {:ok, work} = one_work()
      {:ok, nomen} = Catalog.create_nomen(%{res_id: work.id, nomen_string: "Unchanged"})

      before = Catalog.get_nomen(nomen.id)
      Resolution.resolve(work.id, %Profile{})

      assert Catalog.get_nomen(nomen.id).updated_at == before.updated_at
    end
  end

  describe "15. Replacing the seed set preserves local names and corrections" do
    test "a local name on a seeded res survives the replacement" do
      :ok = Seeds.load(seed_fixture_dir())
      seeded_res = "01a06ddf-9f40-793c-9b87-6af90e5df151"

      {:ok, correction} =
        Catalog.create_nomen(%{
          res_id: seeded_res,
          nomen_string: "Reykjavik, the one we mean",
          provenance: :local
        })

      :ok = Seeds.replace(seed_fixture_dir())

      assert Catalog.get_nomen(correction.id)
      assert Resolution.resolve(seeded_res, %Profile{}).id == correction.id
    end

    test "shipped names are rewritten rather than duplicated" do
      :ok = Seeds.load(seed_fixture_dir())
      seeded_res = "01a06ddf-9f40-793c-9b87-6af90e5df151"

      before = length(Catalog.nomens_for(seeded_res))
      :ok = Seeds.replace(seed_fixture_dir())

      assert length(Catalog.nomens_for(seeded_res)) == before
    end
  end

  describe "16. A user correction survives a subsequent automatic matching run" do
    test "the correction is untouched and still wins" do
      {:ok, work} = an_unnamed_res()

      {:ok, _matched} =
        Catalog.create_nomen(%{
          res_id: work.id,
          nomen_string: "Wrong Title From Matching",
          scheme: "tmdb",
          provenance: :automatic
        })

      {:ok, correction} =
        Catalog.create_nomen(%{
          res_id: work.id,
          nomen_string: "The title it actually is",
          provenance: :local
        })

      rerun_automatic_matching(work.id, "A Different Wrong Title")

      assert Catalog.get_nomen(correction.id)
      assert Resolution.resolve(work.id, %Profile{}).id == correction.id
    end
  end

  describe "17. A temporal selector against a work is rejected; against an expression accepted" do
    test "a cue timed against the work is refused, because two cuts run different lengths" do
      %{work: work} = a_film()

      assert {:error, :address, changeset, _changes} =
               Catalog.create_address(work.id, a_cue())

      assert %{target_kind: [message | _]} = errors_on(changeset)
      assert message =~ "temporal selector is not valid against a work"
    end

    test "the same cue against the expression is accepted" do
      %{expression: expression} = a_film()

      assert {:ok, %{address: address}} = Catalog.create_address(expression.id, a_cue())

      assert address.target_kind == :expression
      assert address.start_ms == 140_000
      assert Catalog.addresses_of(expression.id) == [address]
    end

    test "the database refuses it too, not only the changeset" do
      %{work: work} = a_film()

      error =
        assert_raise Postgrex.Error, fn -> insert_address_directly(work.id, :work, a_cue()) end

      assert error.postgres.constraint == "selector_is_valid_at_target_level"
    end

    test "a region of a frame is bounded at manifestation, since resolution differs per scan" do
      %{expression: expression, manifestation: manifestation} = a_film()

      assert {:error, :address, _changeset, _changes} =
               Catalog.create_address(expression.id, a_region())

      assert {:ok, %{address: address}} = Catalog.create_address(manifestation.id, a_region())
      assert address.selector_type == :spatial
    end

    test "the recorded level cannot disagree with the res the address names" do
      %{expression: expression} = a_film()

      error =
        assert_raise Postgrex.Error, fn ->
          insert_address_directly(expression.id, :manifestation, a_region())
        end

      assert error.postgres.constraint == "addresses_target_id_fkey"
    end
  end

  describe "18. A selector storing byte offsets or frame numbers is rejected" do
    test "no column exists that could hold one" do
      permitted =
        ~w(id target_id target_kind selector_type start_ms end_ms x_percent y_percent
           width_percent height_percent text_unit start_offset end_offset quote_exact
           quote_prefix quote_suffix page_number derivation_id inserted_at updated_at)a

      assert Enum.sort(Address.__schema__(:fields)) == Enum.sort(permitted)
    end

    test "a link timed in SMPTE frames is refused rather than converted" do
      %{expression: expression} = a_film()

      assert {:error, {:forbidden_basis, "smpte"}} =
               DeepLink.parse("/expressions/#{expression.id}?t=smpte:00:00:05:10")
    end

    test "a bare xywh is pixel coordinates in the base grammar, and is refused" do
      %{manifestation: manifestation} = a_film()

      assert {:error, {:forbidden_basis, "pixel"}} =
               DeepLink.parse("/manifestations/#{manifestation.id}?xywh=25,25,50,50")

      assert {:error, {:forbidden_basis, "pixel"}} =
               DeepLink.parse("/manifestations/#{manifestation.id}?xywh=pixel:25,25,50,50")
    end

    test "a byte range is not a dimension this system knows" do
      %{expression: expression} = a_film()

      assert {:error, {:unknown_dimension, "bytes"}} =
               DeepLink.parse("/expressions/#{expression.id}?bytes=0,1024")

      assert {:error, {:unknown_dimension, "frame"}} =
               DeepLink.parse("/expressions/#{expression.id}?frame=1200")
    end

    test "a text offset counts characters or words, never bytes" do
      %{expression: expression} = a_film()

      assert {:error, :address, changeset, _changes} =
               Catalog.create_address(expression.id, %{
                 selector_type: :text_position,
                 text_unit: :byte,
                 start_offset: 0,
                 end_offset: 1024
               })

      assert %{text_unit: [_ | _]} = errors_on(changeset)
    end

    test "a percentage region that runs off the edge of the frame addresses nothing" do
      %{manifestation: manifestation} = a_film()

      assert {:error, :address, changeset, _changes} =
               Catalog.create_address(manifestation.id, %{
                 selector_type: :spatial,
                 x_percent: 80.0,
                 y_percent: 10.0,
                 width_percent: 50.0,
                 height_percent: 10.0
               })

      assert %{width_percent: [_ | _]} = errors_on(changeset)
    end
  end

  describe "19. Normalized position changes when the resource's recorded extent is corrected" do
    test "the midpoint of a film moves when its runtime is measured properly" do
      %{expression: expression} = a_film()
      {:ok, _} = Addressing.record_extent(expression.id, :millisecond, 5_400_000)

      {:ok, %{address: address}} =
        Catalog.create_address(expression.id, %{
          selector_type: :temporal,
          start_ms: 2_700_000,
          end_ms: 2_700_000
        })

      assert Addressing.normalized_position(address) == {0.5, 0.5}

      {:ok, _} = Addressing.record_extent(expression.id, :millisecond, 5_600_000)

      {corrected, _end} = Addressing.normalized_position(address)
      assert_in_delta corrected, 0.482, 0.001
    end

    test "the fraction is derived on demand and is not a column" do
      refute :normalized_start in Address.__schema__(:fields)
      refute :normalized_end in Address.__schema__(:fields)
    end

    test "page forty-two lands elsewhere once the front matter is counted" do
      %{manifestation: manifestation} = a_film()
      {:ok, _} = Addressing.record_extent(manifestation.id, :page, 300)

      {:ok, %{address: address}} =
        Catalog.create_address(manifestation.id, %{selector_type: :page, page_number: 42})

      {before_correction, _end} = Addressing.normalized_position(address)

      {:ok, _} = Addressing.record_extent(manifestation.id, :page, 312)
      {after_correction, _end} = Addressing.normalized_position(address)

      assert before_correction == 41 / 300
      assert after_correction == 41 / 312
    end

    test "a word index and a character offset normalize against different extents" do
      %{expression: expression} = a_film()
      {:ok, _} = Addressing.record_extent(expression.id, :character, 480_000)
      {:ok, _} = Addressing.record_extent(expression.id, :word, 80_000)

      {:ok, %{address: by_character}} =
        Catalog.create_address(expression.id, %{
          selector_type: :text_position,
          text_unit: :character,
          start_offset: 240_000,
          end_offset: 240_100
        })

      {:ok, %{address: by_word}} =
        Catalog.create_address(expression.id, %{
          selector_type: :text_position,
          text_unit: :word,
          start_offset: 40_000,
          end_offset: 40_020
        })

      assert {0.5, _} = Addressing.normalized_position(by_character)
      assert {0.5, _} = Addressing.normalized_position(by_word)
    end

    test "a region of a frame marks no position along the whole" do
      %{manifestation: manifestation} = a_film()

      {:ok, %{address: address}} = Catalog.create_address(manifestation.id, a_region())

      assert_raise Addressing.NotNormalizableError, fn ->
        Addressing.normalized_position(address)
      end
    end

    test "an unrecorded extent raises rather than being guessed at" do
      %{expression: expression} = a_film()

      {:ok, %{address: address}} = Catalog.create_address(expression.id, a_cue())

      assert_raise Addressing.NoExtentError, fn ->
        Addressing.normalized_position(address)
      end
    end
  end

  describe "20. A deep link carrying a selector in the fragment rather than the query" do
    test "is normalized onto the query string" do
      %{expression: expression} = a_film()

      assert {:ok, parsed} = DeepLink.parse("/expressions/#{expression.id}#t=140,148")

      assert parsed.source == :fragment
      assert parsed.canonical == "/expressions/#{expression.id}?t=140,148"
      assert parsed.start_ms == 140_000
    end

    test "is refused where the query carries one too, since the two may disagree" do
      %{expression: expression} = a_film()

      assert {:error, :selector_in_both_query_and_fragment} =
               DeepLink.parse("/expressions/#{expression.id}?t=140,148#t=200,210")
    end

    test "a fragment carrying no selector is left to the client" do
      %{expression: expression} = a_film()

      assert {:ok, parsed} = DeepLink.parse("/expressions/#{expression.id}?t=140,148#notes")
      assert parsed.source == :query
    end

    test "nothing this system builds carries a selector in the fragment" do
      %{expression: expression, manifestation: manifestation} = a_film()

      {:ok, %{address: cue}} = Catalog.create_address(expression.id, a_cue())
      {:ok, %{address: region}} = Catalog.create_address(manifestation.id, a_region())

      for address <- [cue, region] do
        link = DeepLink.build(address)

        refute String.contains?(link, "#")
        assert {:ok, _parsed} = DeepLink.parse(link)
      end
    end

    test "a temporal deep link must name the expression, not the work" do
      %{work: work} = a_film()

      assert {:error, {:selector_invalid_at_level, :temporal, :work}} =
               DeepLink.parse("/works/#{work.id}?t=140,148")
    end

    test "every selector type round-trips through its link" do
      %{expression: expression, manifestation: manifestation} = a_film()

      selectors = [
        {expression, a_cue()},
        {manifestation, a_region()},
        {expression,
         %{selector_type: :text_position, text_unit: :word, start_offset: 200, end_offset: 240}},
        {manifestation, %{selector_type: :page, page_number: 42}},
        {expression,
         %{
           selector_type: :text_quote,
           quote_exact: "it was a bright cold day",
           quote_prefix: "and ",
           quote_suffix: " in April"
         }},
        {manifestation,
         %{
           selector_type: :spatiotemporal,
           start_ms: 140_500,
           end_ms: 148_250,
           x_percent: 25.0,
           y_percent: 25.0,
           width_percent: 50.0,
           height_percent: 50.0
         }}
      ]

      for {target, selector} <- selectors do
        {:ok, %{address: address}} = Catalog.create_address(target.id, selector)

        link = DeepLink.build(address)

        assert {:ok, parsed} = DeepLink.parse(link)
        assert parsed.canonical == link
        assert parsed.selector_type == address.selector_type
      end
    end

    test "fractional seconds survive the round trip" do
      %{expression: expression} = a_film()

      {:ok, %{address: address}} =
        Catalog.create_address(expression.id, %{
          selector_type: :temporal,
          start_ms: 140_500,
          end_ms: 148_004
        })

      assert DeepLink.build(address) == "/expressions/#{expression.id}?t=140.5,148.004"
    end
  end

  describe "21. Changing the OIDC issuer for a principal preserves that principal's events" do
    test "a realm rename maps the new composite onto the principal already there" do
      %{principal: principal} = a_household_member()

      assert Principals.rebind_issuer(
               "https://auth.example/realms/home",
               "https://login.example/realms/household",
               "b4c2"
             ) == 1

      assert Principals.principal_for("https://auth.example/realms/home", "b4c2") == nil

      assert Principals.principal_for("https://login.example/realms/household", "b4c2").id ==
               principal.id
    end

    test "and every event recorded before the move is still theirs" do
      %{principal: principal, work: work} = a_household_member()

      {:ok, _} = Events.record(principal.id, work.id, "played")
      {:ok, _} = Events.record(principal.id, work.id, "played")

      Principals.rebind_issuer(
        "https://auth.example/realms/home",
        "https://login.example/realms/household",
        "b4c2"
      )

      moved = Principals.principal_for("https://login.example/realms/household", "b4c2")

      assert [_, _] = Events.for_principal(moved.id)
      assert Events.play_count(moved.id, work.id, "played") == 2
    end

    test "and so is the position they had reached" do
      %{principal: principal, work: work} = a_household_member()

      {:ok, _} = Events.set_resume_position(principal.id, work.id, 1_820_000)

      Principals.rebind_issuer(
        "https://auth.example/realms/home",
        "https://login.example/realms/household",
        "b4c2"
      )

      assert Events.resume_position(principal.id, work.id).position_ms == 1_820_000
    end

    test "nothing but the identity row holds the composite" do
      for schema <- [Principal, Event, ResumePosition] do
        fields = schema.__schema__(:fields)

        refute :issuer in fields
        refute :subject in fields
      end

      assert :issuer in Identity.__schema__(:fields)
      assert :subject in Identity.__schema__(:fields)
    end

    test "the same subject under two issuers is two identities, not one" do
      %{principal: principal} = a_household_member()

      assert {:ok, _} =
               Principals.bind_identity(principal.id, "https://other.example", "b4c2")

      assert [_, _] = Principals.identities_of(principal.id)
    end
  end

  describe "22. Principal A cannot observe principal B's events through any endpoint" do
    test "an event list holds only the principal it was asked about" do
      %{principal: ada, work: work} = a_household_member()
      %{principal: bo} = another_household_member()

      {:ok, _} = Events.record(ada.id, work.id, "played")
      {:ok, _} = Events.record(bo.id, work.id, "played")

      assert [event] = Events.for_principal(ada.id)
      assert event.principal_id == ada.id
    end

    test "a play count is counted for one principal and not the household" do
      %{principal: ada, work: work} = a_household_member()
      %{principal: bo} = another_household_member()

      for _ <- 1..3, do: {:ok, _} = Events.record(ada.id, work.id, "played")
      {:ok, _} = Events.record(bo.id, work.id, "played")

      assert Events.play_count(ada.id, work.id, "played") == 3
      assert Events.play_count(bo.id, work.id, "played") == 1
    end

    test "a resumption list does not carry what somebody else left part-way" do
      %{principal: ada, work: work} = a_household_member()
      %{principal: bo} = another_household_member()

      {:ok, _} = Events.set_resume_position(ada.id, work.id, 1_820_000)
      {:ok, _} = Events.set_resume_position(bo.id, work.id, 640_000)

      assert [position] = Events.resumable(ada.id)
      assert position.position_ms == 1_820_000
      assert Events.resume_position(ada.id, work.id).position_ms == 1_820_000
    end

    test "no function in the events module answers without being told whose events" do
      exported = Enum.sort(Pluteus.Events.__info__(:functions))

      assert exported == [
               for_principal: 1,
               play_count: 3,
               record: 3,
               record: 4,
               resumable: 1,
               resume_position: 2,
               set_resume_position: 3
             ]
    end
  end

  describe "23. An agent with no principal can be recorded as the assigner of a nomen" do
    test "a child who has never logged in names their grandmother" do
      %{child: child, childs_own: childs_own} = CatalogFixtures.kin_term!()

      assert childs_own.assigner_id == child.id
      assert childs_own.assigner_kind == :person
      assert Repo.all(from p in Principal, where: p.person_id == ^child.id) == []
    end

    test "a collective agent may assign one too" do
      %{agent: agent} = CatalogFixtures.united_nations!()
      work = CatalogFixtures.work!()

      {:ok, nomen} =
        Catalog.create_nomen(%{
          res_id: work.id,
          nomen_string: "Charter of the United Nations",
          assigner_id: agent.id
        })

      assert nomen.assigner_kind == :collective_agent
    end

    test "a place is not an agent and cannot assign a name" do
      {:ok, place} = Catalog.create_res(%{kind: :place})
      work = CatalogFixtures.work!()

      assert {:error, changeset} =
               Catalog.create_nomen(%{
                 res_id: work.id,
                 nomen_string: "Grand Rapids, 1954",
                 assigner_id: place.id
               })

      assert %{assigner_kind: [_ | _]} = errors_on(changeset)
    end

    test "a principal is not a res, so it cannot be an assigner either" do
      %{principal: principal} = a_household_member()
      work = CatalogFixtures.work!()

      assert {:error, :no_such_assigner} =
               Catalog.create_nomen(%{
                 res_id: work.id,
                 nomen_string: "whatever Ada calls it",
                 assigner_id: principal.id
               })
    end

    test "the person behind a principal assigns as the person, not as the principal" do
      {:ok, ada} = Catalog.create_res(%{kind: :person})
      {:ok, principal} = Principals.create_principal(%{role: "member", person_id: ada.id})
      work = CatalogFixtures.work!()

      {:ok, nomen} =
        Catalog.create_nomen(%{
          res_id: work.id,
          nomen_string: "the one with the boat",
          assigner_id: ada.id
        })

      assert principal.person_id == ada.id
      assert nomen.assigner_id == ada.id
      refute nomen.assigner_id == principal.id
    end

    test "the deployment acts as a principal and corresponds to nobody" do
      {:ok, deployment} = Principals.create_principal(%{role: "deployment"})

      assert is_nil(deployment.person_id)
      assert is_nil(deployment.person_kind)
    end
  end

  describe "24. An asset whose last verification exceeds its interval is reported unverified" do
    test "an asset nobody has ever checked is reported, not assumed sound" do
      asset = a_stored_scan()

      assert is_nil(asset.verified_at)
      assert asset.id in Enum.map(Assets.unverified(), & &1.id)
    end

    test "one checked inside its interval is not reported" do
      asset = a_stored_scan()
      {:ok, _} = Assets.record_verification(asset.id, :verified, days_ago(30))

      refute asset.id in Enum.map(Assets.unverified(), & &1.id)
    end

    test "one whose last success is older than its interval is reported again" do
      asset = a_stored_scan()
      {:ok, _} = Assets.record_verification(asset.id, :verified, days_ago(91))

      assert asset.id in Enum.map(Assets.unverified(), & &1.id)
    end

    test "a mismatch is not a success, so the asset stays unverified" do
      asset = a_stored_scan()
      last_success = days_ago(91)

      {:ok, _} = Assets.record_verification(asset.id, :verified, last_success)
      {:ok, _} = Assets.record_verification(asset.id, :mismatched, days_ago(1))

      assert asset.id in Enum.map(Assets.unverified(), & &1.id)
      assert Repo.get(Asset, asset.id).verified_at == last_success
    end

    test "every attempt is recorded, whether it succeeded or not" do
      asset = a_stored_scan()

      {:ok, _} = Assets.record_verification(asset.id, :verified, days_ago(91))
      {:ok, _} = Assets.record_verification(asset.id, :unreadable, days_ago(60))
      {:ok, _} = Assets.record_verification(asset.id, :mismatched, days_ago(1))

      assert Enum.map(Assets.verifications_of(asset.id), & &1.outcome) ==
               [:verified, :unreadable, :mismatched]
    end

    test "detection does not repair: a mismatch leaves the asset exactly as it was" do
      asset = a_stored_scan()
      {:ok, _} = Assets.record_verification(asset.id, :mismatched, days_ago(1))

      stored = Repo.get(Asset, asset.id)

      assert stored.digest == asset.digest
      assert stored.location == asset.location
    end

    test "an outcome outside the three the spec names is rejected" do
      asset = a_stored_scan()

      assert {:error, :verification, changeset, _changes} =
               Assets.record_verification(asset.id, :probably_fine, days_ago(1))

      assert %{outcome: [_ | _]} = errors_on(changeset)
    end
  end

  describe "25. Normalizing a lossy acquisition writes no second copy" do
    test "the lossy acquisition carries the Normalized role itself" do
      asset = a_stored_scan(%{essence: :lossy})

      assert Asset.normalization_plan(asset) == :adopt

      {:ok, _} = Assets.adopt_as_normalized(asset.id, "standardized-master")

      assert Assets.role_classes_of(asset.id) == [:acquired, :normalized]
      assert [_one] = Catalog.assets_of(asset.digital_item_id)
    end

    test "normalizing a lossless acquisition into the standard codec is accepted" do
      asset = a_stored_scan()

      assert Asset.normalization_plan(asset) == :re_encode

      assert {:ok, %{normalized: normalized}} =
               Assets.normalize(
                 asset.id,
                 a_scan(%{
                   location: "/masters/1943-04-12.jxl",
                   roles: []
                 }),
                 "1943-04-12.jxl"
               )

      refute normalized.id == asset.id
      assert Assets.role_classes_of(normalized.id) == [:normalized]
      assert [_, _] = Catalog.assets_of(asset.digital_item_id)
    end

    test "re-encoding lossy essence is rejected" do
      asset = a_stored_scan(%{essence: :lossy})

      assert {:error, :source, :lossy_essence_must_not_be_re_encoded, _changes} =
               Assets.normalize(
                 asset.id,
                 a_scan(%{location: "/masters/1943-04-12.flac", roles: []}),
                 "1943-04-12.flac"
               )

      assert [_one] = Catalog.assets_of(asset.digital_item_id)
    end

    test "one byte sequence bearing two roles is one row, not two" do
      asset = a_stored_scan(%{essence: :lossy})
      {:ok, _} = Assets.adopt_as_normalized(asset.id, "standardized-master")

      assert [_, _] = Assets.roles_of(asset.id)
      assert Repo.aggregate(from(a in Asset, where: a.id == ^asset.id), :count) == 1
    end
  end

  describe "26. Deleting an acquired original deletes its normalized copy" do
    test "the copy goes with the original that supported it" do
      %{acquired: acquired, normalized: normalized} = an_original_and_its_master()

      recycling = recycle!(acquired.id)

      assert Enum.sort(assets_in(recycling)) == Enum.sort([acquired.id, normalized.id])

      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())

      assert Catalog.assets_of(acquired.digital_item_id) == []
    end

    test "the coupling runs one way: deleting the copy leaves the original" do
      %{acquired: acquired, normalized: normalized} = an_original_and_its_master()

      recycling = recycle!(normalized.id)
      assert assets_in(recycling) == [normalized.id]

      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())

      assert [remaining] = Catalog.assets_of(acquired.digital_item_id)
      assert remaining.id == acquired.id
    end

    test "where one asset holds both roles there is nothing to couple to" do
      asset = a_stored_scan(%{essence: :lossy})
      {:ok, _} = Assets.adopt_as_normalized(asset.id, "standardized-master")

      assert assets_in(recycle!(asset.id)) == [asset.id]
    end

    test "except where the original was discarded under spec-03 §4.3" do
      %{acquired: acquired, normalized: recompression} = an_original_and_its_master()
      {:ok, _} = Assets.add_role(recompression.id, :acquired, "jpeg-xl-recompression")

      recycling = recycle!(acquired.id)

      assert assets_in(recycling) == [acquired.id]

      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())

      assert [standing] = Catalog.assets_of(acquired.digital_item_id)
      assert standing.id == recompression.id
      assert Assets.role_classes_of(recompression.id) == [:acquired, :normalized]
    end

    test "purging an asset takes its roles with it" do
      %{acquired: acquired} = an_original_and_its_master()

      purge!(acquired.id)

      assert Assets.roles_of(acquired.id) == []
    end
  end

  describe "29. An asset referencing two digital items is rejected" do
    test "the digital item an asset realizes is single-valued" do
      %{digital_item: digital_item} = a_scanned_letter()

      {:ok, %{asset: asset}} =
        Catalog.create_asset(digital_item.id, a_scan(), "1943-04-12.tiff")

      assert asset.digital_item_id == digital_item.id
      assert Assets.role_classes_of(asset.id) == [:acquired]
    end

    test "an asset realizing no digital item is rejected" do
      {:ok, res} = Catalog.create_res(%{kind: :asset})

      assert {:error, changeset} =
               %Asset{}
               |> Asset.changeset(Map.merge(a_scan(), %{id: res.id}))
               |> Repo.insert()

      assert %{digital_item_id: [_ | _]} = errors_on(changeset)
    end

    test "a role outside the four normative classes is rejected" do
      %{digital_item: digital_item} = a_scanned_letter()

      assert {:error, {:asset_role, 0}, changeset, _changes} =
               Catalog.create_asset(
                 digital_item.id,
                 a_scan(%{roles: [%{role_class: :working_copy, role: "scratch"}]}),
                 "scratch.tiff"
               )

      assert %{role_class: [_ | _]} = errors_on(changeset)
    end
  end

  describe "30. A digital item with zero assets is accepted and renders" do
    test "a holding whose copies are all lost is still catalogued" do
      %{digital_item: digital_item} = a_scanned_letter()

      assert Catalog.assets_of(digital_item.id) == []
      assert %DigitalItem{} = Repo.get(DigitalItem, digital_item.id)
    end

    test "and it still resolves to the name it was catalogued under" do
      %{digital_item: digital_item} = a_scanned_letter()

      CatalogFixtures.nomen!(digital_item.id, %{
        nomen_string: "Letter from Ada, 12 April 1943"
      })

      assert Resolution.resolve(digital_item.id, %Profile{}).nomen_string ==
               "Letter from Ada, 12 April 1943"
    end

    test "losing every copy does not remove the holding" do
      %{digital_item: digital_item} = a_scanned_letter()

      {:ok, %{asset: asset}} =
        Catalog.create_asset(digital_item.id, a_scan(), "1943-04-12.tiff")

      purge!(asset.id)

      assert Catalog.assets_of(digital_item.id) == []
      assert %DigitalItem{} = Repo.get(DigitalItem, digital_item.id)
    end
  end

  describe "31. A derived asset creates no manifestation or digital item" do
    test "a thumbnail, a waveform and a transcript all sit under the existing holding" do
      %{digital_item: digital_item} = a_scanned_letter()

      manifestations_before = Repo.aggregate(Manifestation, :count)
      digital_items_before = Repo.aggregate(DigitalItem, :count)

      for {role, location} <- [
            {"thumbnail", "/derived/1943-04-12.thumb.jpg"},
            {"waveform", "/derived/1943-04-12.peaks.json"},
            {"machine-transcript", "/derived/1943-04-12.ocr.txt"}
          ] do
        {:ok, %{asset: asset}} =
          Catalog.create_asset(
            digital_item.id,
            a_scan(%{
              location: location,
              roles: [%{role_class: :derived, role: role}]
            }),
            Path.basename(location)
          )

        assert Assets.role_classes_of(asset.id) == [:derived]
      end

      assert Repo.aggregate(Manifestation, :count) == manifestations_before
      assert Repo.aggregate(DigitalItem, :count) == digital_items_before
    end

    test "and none of them is worth backup capacity" do
      refute AssetRole.backed_up?(:derived)
      assert AssetRole.backed_up?(:acquired)
      assert AssetRole.backed_up?(:normalized)
    end
  end

  describe "32. Deleting every asset preserves arrangement within the aggregate" do
    test "track three of an album stays track three when the file is gone" do
      %{album_expression: album, track_expression: track, digital_item: digital_item} =
        an_album_track()

      assert Catalog.arrange(album.id, track.id, 3) == 1
      assert Catalog.arrangement_of(album.id, track.id) == 3

      {:ok, %{asset: asset}} =
        Catalog.create_asset(
          digital_item.id,
          a_scan(%{location: "/music/album/03.flac"}),
          "03.flac"
        )

      purge!(asset.id)

      assert Catalog.assets_of(digital_item.id) == []
      assert Catalog.arrangement_of(album.id, track.id) == 3
    end

    test "arrangement is not a column on the asset" do
      refute :arrangement in Asset.__schema__(:fields)
      refute :role_class in Asset.__schema__(:fields)
      assert :part_sequence in Asset.__schema__(:fields)
    end
  end

  describe "36. Recycling an asset leaves its bytes byte-identical; restoring returns them" do
    test "the bytes in the bin are the bytes that went in" do
      %{asset: asset, bytes: bytes} = a_letter_on_disk()

      recycle!(asset.id)

      assert Storage.read(asset.location) == bytes
      assert sha256(Storage.read(asset.location)) == asset.digest
    end

    test "and restoring hands back those same bytes at the same location" do
      %{asset: asset, bytes: bytes} = a_letter_on_disk()

      recycling = recycle!(asset.id)
      {:ok, _restored} = Lifecycle.restore(recycling.id)

      assert {:live, _res} = Lifecycle.state(asset.id)
      assert Repo.get(Asset, asset.id).location == asset.location
      assert Storage.read(asset.location) == bytes
    end

    test "recycling the whole work moves no byte of any asset below it" do
      %{asset: asset, bytes: bytes, work: work} = a_letter_on_disk()

      recycling = recycle!(work.id)

      assert asset.id in Lifecycle.contents(recycling.id)
      assert Storage.read(asset.location) == bytes
    end
  end

  describe "37. Purging removes the bytes and leaves a tombstone that blocks reuse" do
    test "the bytes are gone from primary storage" do
      %{asset: asset} = a_letter_on_disk()

      %{bytes_not_removed: []} = purge!(asset.id)

      refute Storage.exists?(asset.location)
    end

    test "the tombstone records the identifier, the class and the time of purge" do
      %{asset: asset} = a_letter_on_disk()
      now = DateTime.utc_now()

      recycling = recycle!(asset.id)
      {:ok, _} = Lifecycle.purge(recycling, now)

      assert %Tombstone{kind: :asset, purged_at: ^now} = Repo.get(Tombstone, asset.id)
      assert {:purged, %Res{kind: :asset}, _tombstone} = Lifecycle.state(asset.id)
    end

    test "the identifier cannot be minted again" do
      %{asset: asset} = a_letter_on_disk()
      purge!(asset.id)

      assert {:error, changeset} = Catalog.create_res(%{id: asset.id, kind: :asset})
      assert %{id: [_ | _]} = errors_on(changeset)
    end

    test "the asset's own row goes, while history recorded against the work stays" do
      %{asset: asset, work: work} = a_letter_on_disk()
      {:ok, principal} = Principals.create_principal(%{role: "member"})
      {:ok, event} = Events.record(principal.id, work.id, "read")

      purge!(work.id)

      assert Repo.get(Asset, asset.id) == nil
      assert Repo.get(Work, work.id) == nil
      assert [%Event{id: id}] = Events.for_principal(principal.id)
      assert id == event.id
    end

    test "a byte sequence that could not be removed is reported, not swallowed" do
      %{asset: asset} = a_letter_on_disk()
      :ok = Storage.delete(asset.location)

      assert %{bytes_not_removed: [{location, :enoent}]} = purge!(asset.id)
      assert location == asset.location
    end
  end

  describe "34. A local row and a later release's seed for one concept both persist and link" do
    test "the household's own row survives the release that ships a seed for the same place" do
      %{local: local, seeded: seeded} = a_place_the_household_named_first()

      assert Catalog.get_res(local.id)
      assert Catalog.get_res(seeded.id)
      refute local.id == seeded.id
    end

    test "they are linked rather than merged, in either direction" do
      %{local: local, seeded: seeded} = a_place_the_household_named_first()

      {:ok, _} = Catalog.associate(local.id, seeded.id, Association.same_thing())

      assert Catalog.associated(local.id, Association.same_thing()) == [seeded.id]
      assert Catalog.associated(seeded.id, Association.same_thing()) == [local.id]
    end

    test "resolution over either row returns the household's own name" do
      %{local: local, seeded: seeded} = a_place_the_household_named_first()

      {:ok, _} = Catalog.associate(local.id, seeded.id, Association.same_thing())

      assert Resolution.resolve(local.id, %Profile{}).nomen_string == "Grandma's house"
      assert Resolution.resolve(seeded.id, %Profile{}).nomen_string == "Grandma's house"
    end

    test "unlinked, the seeded row still answers under its shipped name" do
      %{seeded: seeded} = a_place_the_household_named_first()

      assert Resolution.resolve(seeded.id, %Profile{}).nomen_string ==
               "Kregel Residence, Grand Rapids"
    end

    test "the shipped name is not mutated by the link" do
      %{local: local, seeded: seeded} = a_place_the_household_named_first()

      {:ok, _} = Catalog.associate(local.id, seeded.id, Association.same_thing())

      assert [%Nomen{provenance: :seeded, nomen_string: "Kregel Residence, Grand Rapids"}] =
               Catalog.nomens_for(seeded.id)
    end

    test "a res is not one thing with itself" do
      %{local: local} = a_place_the_household_named_first()

      assert {:error, changeset} =
               Catalog.associate(local.id, local.id, Association.same_thing())

      assert %{object_id: [_ | _]} = errors_on(changeset)
    end

    test "the same link is not recorded twice" do
      %{local: local, seeded: seeded} = a_place_the_household_named_first()

      {:ok, _} = Catalog.associate(local.id, seeded.id, Association.same_thing())

      assert {:error, changeset} =
               Catalog.associate(local.id, seeded.id, Association.same_thing())

      assert %{subject_id: [_ | _]} = errors_on(changeset)
    end
  end

  describe "35. A digital item referencing two manifestations is rejected" do
    test "the manifestation a digital item carries is single-valued" do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("Odyssey")

      {:ok, %{digital_item: digital_item}} =
        Catalog.create_digital_item(manifestation.id, "Odyssey.mkv")

      assert digital_item.manifestation_id == manifestation.id
      refute :manifestation_ids in DigitalItem.__schema__(:fields)
    end

    test "a digital item carrying no manifestation at all is rejected" do
      {:ok, res} = Catalog.create_res(%{kind: :digital_item})

      assert {:error, changeset} =
               %DigitalItem{} |> DigitalItem.changeset(%{id: res.id}) |> Repo.insert()

      assert %{manifestation_id: [_ | _]} = errors_on(changeset)
    end

    test "a manifestation the household describes but holds no file for is accepted" do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("Odyssey")

      assert Repo.all(from d in DigitalItem, where: d.manifestation_id == ^manifestation.id) == []
      assert %Manifestation{} = Repo.get(Manifestation, manifestation.id)
    end

    test "and it renders under the name it was catalogued with" do
      {:ok, %{manifestation: manifestation}} =
        Catalog.create_work("Hokusai, Great Wave, 1831 printing")

      assert Resolution.resolve(manifestation.id, %Profile{}).nomen_string ==
               "Hokusai, Great Wave, 1831 printing"
    end
  end

  # A person with a login, the work they were watching, and the provider that
  # knows them.
  defp a_household_member do
    {:ok, person} = Catalog.create_res(%{kind: :person})
    {:ok, principal} = Principals.create_principal(%{role: "member", person_id: person.id})

    {:ok, _} =
      Principals.bind_identity(principal.id, "https://auth.example/realms/home", "b4c2")

    %{person: person, principal: principal, work: CatalogFixtures.work!()}
  end

  defp another_household_member do
    {:ok, person} = Catalog.create_res(%{kind: :person})
    {:ok, principal} = Principals.create_principal(%{role: "member", person_id: person.id})

    {:ok, _} =
      Principals.bind_identity(principal.id, "https://auth.example/realms/home", "9f11")

    %{person: person, principal: principal}
  end

  # The household named a place before any release shipped a seed for it. §7.5
  # leaves both rows standing.
  defp a_place_the_household_named_first do
    {:ok, local} = Catalog.create_res(%{kind: :place})

    {:ok, _} =
      Catalog.create_nomen(%{
        res_id: local.id,
        nomen_string: "Grandma's house",
        provenance: :local
      })

    {:ok, seeded} = Catalog.create_res(%{kind: :place})

    {:ok, _} =
      Catalog.create_nomen(%{
        res_id: seeded.id,
        nomen_string: "Kregel Residence, Grand Rapids",
        provenance: :seeded
      })

    %{local: local, seeded: seeded}
  end

  # A film: one work, one expression, one manifestation embodying it.
  defp a_film do
    {:ok, %{work: work, expression: expression, manifestation: manifestation}} =
      Catalog.create_work("The Dig")

    %{work: work, expression: expression, manifestation: manifestation}
  end

  defp a_cue, do: %{selector_type: :temporal, start_ms: 140_000, end_ms: 148_000}

  defp a_region do
    %{
      selector_type: :spatial,
      x_percent: 25.0,
      y_percent: 25.0,
      width_percent: 50.0,
      height_percent: 50.0
    }
  end

  # Bypasses the changeset so that the database's own refusal is what is under
  # test, rather than the validation standing in front of it.
  defp insert_address_directly(target_id, target_kind, selector) do
    {:ok, res} = Catalog.create_res(%{kind: :address})
    now = DateTime.utc_now()

    row =
      selector
      |> Map.merge(%{id: res.id, target_id: target_id, target_kind: target_kind})
      |> Map.merge(%{inserted_at: now, updated_at: now})

    Repo.insert_all(Address, [row])
  end

  defp uuidv7?(uuid) do
    match?({:ok, <<_::48, 7::4, _::12, 2::2, _::62>>}, Ecto.UUID.dump(uuid))
  end

  defp seed_fixture_dir, do: Path.expand("../../fixtures/seeds", __DIR__)

  defp seeded_ids do
    Res
    |> Repo.all()
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  # A scanned letter whose bytes are really in primary storage, under a location
  # no other test writes to.
  defp a_letter_on_disk do
    {:ok, %{work: work, manifestation: manifestation}} =
      Catalog.create_work("Letter from Ada, 12 April 1943")

    {:ok, %{digital_item: digital_item}} =
      Catalog.create_digital_item(manifestation.id, "Letter from Ada, 12 April 1943")

    attrs = a_scan()

    {:ok, %{asset: asset}} = Catalog.create_asset(digital_item.id, attrs, "1943-04-12.tiff")

    %{work: work, asset: asset, bytes: Storage.read(attrs.location)}
  end

  defp sha256(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)

  defp recycle!(res_id) do
    {:ok, principal} = Principals.create_principal(%{role: "member"})
    {:ok, recycling} = Lifecycle.recycle(res_id, principal.id)
    recycling
  end

  defp purge!(res_id) do
    {:ok, result} = res_id |> recycle!() |> Lifecycle.purge(DateTime.utc_now())
    result
  end

  defp assets_in(recycling) do
    ids = Lifecycle.contents(recycling.id)
    Repo.all(from a in Asset, where: a.id in ^ids, select: a.id)
  end

  # One stored file, with everything spec-03 §3.2 requires recorded about it.
  defp a_stored_scan(overrides \\ %{}) do
    %{digital_item: digital_item} = a_scanned_letter()

    {:ok, %{asset: asset}} =
      Catalog.create_asset(digital_item.id, a_scan(overrides), "1943-04-12.tiff")

    asset
  end

  # A lossless original and the standardized master made from it.
  defp an_original_and_its_master do
    acquired = a_stored_scan()

    {:ok, %{normalized: normalized}} =
      Assets.normalize(
        acquired.id,
        a_scan(%{location: "/masters/1943-04-12.jxl", roles: []}),
        "1943-04-12.jxl"
      )

    %{acquired: acquired, normalized: normalized}
  end

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days * 24 * 60 * 60, :second)

  # What spec-03 §3.2 requires an asset to record, for a scan of a letter.
  #
  # The bytes are really written, since an asset's size, digest and format are
  # read from them. A location given in `overrides` supplies the file name; the
  # directory is always fresh.
  defp a_scan(overrides \\ %{}) do
    {requested, overrides} = Map.pop(overrides, :location, "letters/1943-04-12.tiff")
    file_name = Path.basename(requested)
    location = StorageFixtures.stored!(file_name, StorageFixtures.png(file_name))

    Map.merge(
      %{
        location: location,
        essence: :lossless,
        verification_interval_seconds: 90 * 24 * 60 * 60,
        roles: [%{role_class: :acquired, role: "original-scan"}]
      },
      overrides
    )
  end

  # A scan of a physical letter: one manifestation, one file carrying it.
  defp a_scanned_letter do
    {:ok, %{manifestation: manifestation}} =
      Catalog.create_work("Letter from Ada, 12 April 1943")

    {:ok, %{digital_item: digital_item}} =
      Catalog.create_digital_item(manifestation.id, "Letter from Ada, 12 April 1943")

    %{manifestation: manifestation, digital_item: digital_item}
  end

  # An album aggregating one track's expression, with the track's file.
  defp an_album_track do
    {:ok, %{expression: album_expression}} = Catalog.create_work("Kind of Blue")

    {:ok, %{expression: track_expression, manifestation: track_manifestation}} =
      Catalog.create_work("So What")

    {:ok, _} = Catalog.aggregate(album_expression.id, track_expression.id)

    {:ok, %{digital_item: digital_item}} =
      Catalog.create_digital_item(track_manifestation.id, "So What")

    %{
      album_expression: album_expression,
      track_expression: track_expression,
      digital_item: digital_item
    }
  end

  defp permutations([]), do: [[]]

  defp permutations(list) do
    for head <- list, tail <- permutations(list -- [head]), do: [head | tail]
  end

  defp one_work do
    {:ok, %{work: work}} = Catalog.create_work("Odyssey")
    {:ok, work}
  end

  # A res the constructors have not named, for tests that need the whole set of
  # names a res carries to be the one they wrote.
  defp an_unnamed_res do
    {:ok, res} = Catalog.create_res(%{kind: :work})
    {:ok, res}
  end

  defp rerun_automatic_matching(res_id, replacement) do
    Repo.delete_all(from n in Nomen, where: n.res_id == ^res_id and n.provenance == :automatic)

    {:ok, _} =
      Catalog.create_nomen(%{
        res_id: res_id,
        nomen_string: replacement,
        scheme: "tmdb",
        provenance: :automatic
      })
  end

  defp tmp_seed_dir(contents) do
    dir = Path.join(System.tmp_dir!(), "pluteus-seed-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "seed.json"), contents)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end
end
