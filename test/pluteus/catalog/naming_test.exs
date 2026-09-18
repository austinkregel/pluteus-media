defmodule Pluteus.Catalog.NamingTest do
  @moduledoc """
  Naming behaviour spec-01 §7 requires that §15 does not enumerate.

  The numbered criteria check that resolution returns something and that the
  shipped layer can be swapped. They say nothing about whether a transliteration
  can be recorded, whether a name can belong to no language, or whether one
  person may hold two identifiers. Those are the cases the model was built for.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Catalog.Seeds
  alias Pluteus.CatalogFixtures

  describe "LRM-R13, every res carries a name" do
    test "a res of a named kind created with no nomen is refused at commit" do
      assert_raise Postgrex.Error, fn ->
        Repo.transaction(fn ->
          {:ok, _res} = Catalog.create_res(%{kind: :work})

          Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")
        end)
      end
    end

    test "the constructor names the work, its expression and its manifestation" do
      {:ok, %{work: work, expression: expression, manifestation: manifestation}} =
        Catalog.create_work("The Dig")

      Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")

      for res <- [work, expression, manifestation] do
        assert [%Nomen{nomen_string: "The Dig"}] = Catalog.nomens_for(res.id)
      end
    end

    test "those are three nomens, so retitling one leaves the others alone" do
      {:ok, %{work: work, expression: expression}} = Catalog.create_work("The Dig")

      [work_title] = Catalog.nomens_for(work.id)
      [expression_title] = Catalog.nomens_for(expression.id)

      refute work_title.id == expression_title.id
    end

    test "a nomen is exempt, because naming every name would not end" do
      {:ok, res} = Catalog.create_named_res(:person, "Ada")
      person = res.res

      {:ok, nomen} = Catalog.create_nomen(%{res_id: person.id, nomen_string: "Ada Lovelace"})

      Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")

      assert Catalog.nomens_for(nomen.id) == []
    end

    test "a reified address is exempt, since a name would restate its selector" do
      {:ok, %{expression: expression}} = Catalog.create_work("The Dig")

      {:ok, %{address: address}} =
        Catalog.create_address(expression.id, %{
          selector_type: :temporal,
          start_ms: 140_000,
          end_ms: 148_000
        })

      Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")

      assert Catalog.nomens_for(address.id) == []
    end

    test "the obligation is at creation, so a res may later lose its last name" do
      {:ok, %{work: work}} = Catalog.create_work("The Dig")

      Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")

      {1, _} = Repo.delete_all(from n in Nomen, where: n.res_id == ^work.id)

      Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")

      assert Catalog.nomens_for(work.id) == []
      assert Catalog.get_res(work.id)
    end

    test "seed loading writes an entry's names in the transaction that creates it" do
      :ok = Seeds.load(Path.expand("../../fixtures/seeds", __DIR__))

      Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")

      assert Catalog.get_res("01a06ddf-9f40-793c-9b87-6af90e5df151")
    end
  end

  describe "LRM-R17, one name derived from another" do
    test "a Latin transliteration records the Cyrillic form it came from" do
      %{cyrillic: cyrillic, latin: latin} = CatalogFixtures.anna_pavlova!()

      stored = Catalog.get_nomen(latin.id)

      assert stored.derived_from_id == cyrillic.id
      assert stored.script == "Latn"
      assert stored.script_conversion == "ISO 9"
      assert Catalog.get_nomen(cyrillic.id).script == "Cyrl"
    end

    test "the original records no derivation of its own" do
      %{cyrillic: cyrillic} = CatalogFixtures.anna_pavlova!()

      assert is_nil(Catalog.get_nomen(cyrillic.id).derived_from_id)
    end

    test "a name cannot be derived from a name of a different res" do
      %{cyrillic: cyrillic} = CatalogFixtures.anna_pavlova!()
      other = CatalogFixtures.work!()

      assert {:error, changeset} =
               Catalog.create_nomen(%{
                 res_id: other.id,
                 nomen_string: "Borrowed derivation",
                 derived_from_id: cyrillic.id
               })

      assert %{derived_from_id: [_ | _]} = errors_on(changeset)
    end

    test "the derivation is single-valued, as M to 1 requires" do
      %{latin: latin} = CatalogFixtures.anna_pavlova!()

      assert :derived_from_id in Nomen.__schema__(:fields)
      refute :derived_from_ids in Nomen.__schema__(:fields)
      assert is_binary(Catalog.get_nomen(latin.id).derived_from_id)
    end
  end

  describe "the attributes a nomen carries beyond its string" do
    test "scheme, script, context of use and reference source all round-trip" do
      person = CatalogFixtures.work!()

      nomen =
        CatalogFixtures.nomen!(person.id, %{
          nomen_string: "Christie, Agatha, 1890-1976",
          scheme: "lc-naco",
          language: "en",
          script: "Latn",
          context_of_use: "detective fiction",
          reference_source: "LC/NACO authority file",
          intended_audience: "cataloguers"
        })

      stored = Catalog.get_nomen(nomen.id)

      assert stored.scheme == "lc-naco"
      assert stored.script == "Latn"
      assert stored.context_of_use == "detective fiction"
      assert stored.reference_source == "LC/NACO authority file"
      assert stored.intended_audience == "cataloguers"
    end

    test "one person holds two identifiers, one per bibliographic identity" do
      %{person: person} = CatalogFixtures.agatha_christie!()

      isnis =
        person.id
        |> Catalog.nomens_for()
        |> Enum.filter(&(&1.scheme == "isni"))
        |> Enum.map(& &1.nomen_string)
        |> Enum.sort()

      assert isnis == ["0000000121022127", "0000000366130900"]
    end

    test "context of use separates the two identities without splitting the person" do
      %{person: person} = CatalogFixtures.agatha_christie!()

      contexts =
        person.id
        |> Catalog.nomens_for()
        |> Enum.map(& &1.context_of_use)
        |> Enum.uniq()
        |> Enum.sort()

      assert contexts == ["detective fiction", "romance novels"]
    end
  end

  describe "calendar preference is resolution, not a second mechanism" do
    test "an Italian profile gets the Italian rendering of the same day" do
      %{time_span: time_span} = CatalogFixtures.first_march_2015!()

      assert Resolution.resolve(time_span.id, %Profile{language: "it"}).nomen_string ==
               "1 marzo 2015"
    end

    test "a Hebrew profile gets the Hebrew calendar rendering" do
      %{time_span: time_span} = CatalogFixtures.first_march_2015!()

      resolved = Resolution.resolve(time_span.id, %Profile{language: "he"})

      assert resolved.nomen_string == "10 Adar 5775"
      assert resolved.scheme == "hebrew"
    end

    test "a profile in a language nobody wrote it in still resolves" do
      %{time_span: time_span} = CatalogFixtures.first_march_2015!()

      assert %Nomen{} = Resolution.resolve(time_span.id, %Profile{language: "ja"})
    end
  end

  describe "batch resolution over a list view" do
    test "several res resolve in one pass, each to its own preferred language" do
      %{agent: agent} = CatalogFixtures.united_nations!()
      %{time_span: time_span} = CatalogFixtures.first_march_2015!()

      resolved = Resolution.resolve_many([agent.id, time_span.id], %Profile{language: "it"})

      assert resolved[agent.id].nomen_string == "Nazioni Unite"
      assert resolved[time_span.id].nomen_string == "1 marzo 2015"
    end

    test "a res carrying no visible name is absent rather than nil" do
      %{agent: agent} = CatalogFixtures.united_nations!()

      {:ok, rabbit} = Catalog.create_res(%{kind: :person})
      {:ok, child} = Catalog.create_res(%{kind: :person})

      CatalogFixtures.nomen!(rabbit.id, %{
        nomen_string: "Bunny",
        assigner_id: child.id
      })

      resolved = Resolution.resolve_many([agent.id, rabbit.id], %Profile{})

      assert Map.has_key?(resolved, agent.id)
      refute Map.has_key?(resolved, rabbit.id)
    end

    test "batch and single resolution agree" do
      %{agent: agent} = CatalogFixtures.united_nations!()
      profile = %Profile{language: "fr"}

      batch = Resolution.resolve_many([agent.id], profile)

      assert batch[agent.id].id == Resolution.resolve(agent.id, profile).id
    end
  end

  describe "household vocabulary and one person's variant on it" do
    test "a kin term belonging to no language is stored as written" do
      %{household: household} = CatalogFixtures.kin_term!()

      stored = Catalog.get_nomen(household.id)

      assert stored.nomen_string == "Amma"
      assert is_nil(stored.language)
      assert is_nil(stored.assigner_id)
      assert stored.context_of_use == "maternal grandmother"
    end

    test "the child sees their own variant and everyone else sees the household's" do
      %{grandmother: grandmother, child: child} = CatalogFixtures.kin_term!()

      assert Resolution.resolve(grandmother.id, %Profile{assigner_id: child.id}).nomen_string ==
               "Amma-ji"

      assert Resolution.resolve(grandmother.id, %Profile{}).nomen_string == "Amma"
    end

    test "one person's variant is not shown to another person" do
      %{grandmother: grandmother} = CatalogFixtures.kin_term!()
      {:ok, someone_else} = Catalog.create_res(%{kind: :person})

      assert Resolution.resolve(grandmother.id, %Profile{assigner_id: someone_else.id}).nomen_string ==
               "Amma"
    end
  end
end
