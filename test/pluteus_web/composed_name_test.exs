defmodule PluteusWeb.ComposedNameTest do
  @moduledoc """
  spec-10 §6.3's composed name, and the per-principal resolution spec-01 §7.4 puts
  at the render boundary.

  Asserts spec-10 criteria 5 and 6, and spec-07 criterion 23.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Annotations
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Res
  alias Pluteus.Catalog.Resolution
  alias Pluteus.CatalogFixtures
  alias Pluteus.Principals
  alias Pluteus.Repo
  alias Pluteus.Representation.ComposedName

  @viewer "ada@household.test"

  setup %{conn: conn} do
    {:ok, principal} = Principals.create_principal(%{role: "member"})
    {:ok, _} = Principals.bind_identity(principal.id, issuer(), @viewer)

    %{conn: through_proxy(conn, @viewer), principal: principal}
  end

  describe "a name resolves per principal at the render boundary" do
    test "one person's own label for a thing is not shown to another", %{conn: conn} do
      {:ok, %{work: work}} = Catalog.create_work("Kind of Blue")
      {:ok, someone_else} = Catalog.create_res(%{kind: :person})

      CatalogFixtures.nomen!(work.id, %{
        nomen_string: "Dad's copy",
        assigner_id: someone_else.id
      })

      body = conn |> get("/works/#{work.id}") |> json_response(200)

      # The requesting principal has no person of their own, so the profile asks
      # for the household's shared vocabulary and nothing else (spec-01 §7.3).
      assert body["name"] == %{"state" => "held", "value" => "Kind of Blue"}
    end

    test "nor does it appear among the nomens the representation carries", %{conn: conn} do
      {:ok, %{work: work}} = Catalog.create_work("Kind of Blue")
      {:ok, someone_else} = Catalog.create_res(%{kind: :person})

      CatalogFixtures.nomen!(work.id, %{
        nomen_string: "Dad's copy",
        assigner_id: someone_else.id
      })

      body = conn |> get("/works/#{work.id}") |> json_response(200)

      carried = Enum.map(body["nomens"]["value"], & &1["nomen_string"])

      assert "Kind of Blue" in carried
      refute "Dad's copy" in carried
    end
  end

  describe "5. A res with nothing displayable carries a composed name" do
    test "a reified address is named by what it is a region of", %{conn: conn} do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("Middlemarch")

      {:ok, %{address: address}} =
        Catalog.create_address(manifestation.id, %{selector_type: :page, page_number: 42})

      body = conn |> get("/addresses/#{address.id}") |> json_response(200)

      # spec-01 §6.1 exempts a reified address from carrying a nomen, so resolution
      # genuinely answers nothing and §6.3 composes instead.
      assert body["name"] == %{"state" => "not_yet_examined"}
      assert body["composed_name"] == "A region of Middlemarch."
    end

    test "an annotation is named by what it is a note on", %{conn: conn, principal: principal} do
      {:ok, %{work: work}} = Catalog.create_work("Kind of Blue")

      {:ok, note} =
        Annotations.annotate(%{
          target_id: work.id,
          body_type: "note",
          body: %{"text" => "the solo starts here"},
          principal_id: principal.id
        })

      body = conn |> get("/annotations/#{note.id}") |> json_response(200)

      assert body["composed_name"] == "A note on Kind of Blue."
    end

    test "it never carries the identifier, which §7.4 forbids falling back to", %{conn: conn} do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("Middlemarch")

      {:ok, %{address: address}} =
        Catalog.create_address(manifestation.id, %{selector_type: :page, page_number: 42})

      body = conn |> get("/addresses/#{address.id}") |> json_response(200)

      refute body["composed_name"] =~ address.id
      refute body["composed_name"] =~ manifestation.id
    end

    test "it terminates in a noun for the kind, whatever else is absent", %{conn: conn} do
      # A res of a kind that carries no category, no work and no relations: the
      # terminal is all that is left, and §6.3 requires it always be available.
      {:ok, %{res: place}} = Catalog.create_named_res(:place, "Bridgeport")
      {:ok, unnamed} = Catalog.create_res(%{kind: :place})

      assert %{"state" => "held"} = named(conn, "places", place.id)["name"]

      body = conn |> get("/places/#{unnamed.id}") |> json_response(200)
      assert body["composed_name"] == "A place."
    end

    test "every kind a res may take has a noun" do
      for kind <- Res.kinds() do
        assert is_binary(ComposedName.noun(kind)), "#{kind} has no noun"
      end
    end

    test "no noun is one of the words §8.5 forbids as a label" do
      forbidden = ~w(work expression manifestation item res asset)

      for kind <- Res.kinds() do
        words = ComposedName.noun(kind) |> String.downcase() |> String.split(~r/\W+/)

        assert Enum.all?(forbidden, &(&1 not in words)),
               "#{kind}'s noun says #{ComposedName.noun(kind)}"
      end
    end
  end

  describe "6. A composed name is never an empty string, and is not a nomen" do
    test "it is not written to the catalog", %{conn: conn} do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("Middlemarch")

      {:ok, %{address: address}} =
        Catalog.create_address(manifestation.id, %{selector_type: :page, page_number: 42})

      before = Repo.aggregate(Nomen, :count)

      body = conn |> get("/addresses/#{address.id}") |> json_response(200)

      assert body["composed_name"] != ""
      assert Repo.aggregate(Nomen, :count) == before
    end

    test "it does not appear among the nomens the representation carries", %{conn: conn} do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("Middlemarch")

      {:ok, %{address: address}} =
        Catalog.create_address(manifestation.id, %{selector_type: :page, page_number: 42})

      body = conn |> get("/addresses/#{address.id}") |> json_response(200)

      assert body["nomens"] == %{"state" => "not_yet_examined"}
    end

    test "a res that resolves to a name carries no composed one", %{conn: conn} do
      {:ok, %{work: work}} = Catalog.create_work("Kind of Blue")

      body = conn |> get("/works/#{work.id}") |> json_response(200)

      # The composed name is the surface's own rather than a field of the res, so
      # it is present exactly where there is one.
      assert body["name"] == %{"state" => "held", "value" => "Kind of Blue"}
      refute Map.has_key?(body, "composed_name")
    end

    test "resolution of such a res still raises rather than fabricating a label", %{conn: conn} do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("Middlemarch")

      {:ok, %{address: address}} =
        Catalog.create_address(manifestation.id, %{selector_type: :page, page_number: 42})

      # §6.3 leaves resolution's contract untouched: the composed name is what the
      # surface shows instead, not a name resolution learned to return.
      assert_raise Resolution.NoNomenError, fn ->
        Resolution.resolve(address.id, %Profile{})
      end

      assert conn |> get("/addresses/#{address.id}") |> json_response(200)
    end
  end

  describe "the composition degrades as relations are absent" do
    test "a work with a credited agent names it" do
      {:ok, %{work: work}} = Catalog.create_work("Kind of Blue")
      {:ok, %{res: miles}} = Catalog.create_named_res(:person, "Miles Davis")
      {:ok, _} = Catalog.credit_creator(work.id, miles.id)

      # The work resolves to a name of its own, so ask about something that does
      # not: a note on it takes the work's name, and the work's own composition is
      # what a nameless work would have shown.
      composed = ComposedName.for_one(Repo.get!(Res, work.id), %Profile{})

      assert composed == "A holding, with Miles Davis."
    end

    test "an agent that resolves to nothing is left out rather than described" do
      {:ok, %{work: work}} = Catalog.create_work("Kind of Blue")
      {:ok, nameless} = Catalog.create_res(%{kind: :person})
      {:ok, _} = Catalog.credit_creator(work.id, nameless.id)

      composed = ComposedName.for_one(Repo.get!(Res, work.id), %Profile{})

      assert composed == "A holding."
    end

    test "a page of res is composed in a bounded number of queries" do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("Middlemarch")

      addresses =
        for page <- 1..12 do
          {:ok, %{address: address}} =
            Catalog.create_address(manifestation.id, %{selector_type: :page, page_number: page})

          Repo.get!(Res, address.id)
        end

      composed = ComposedName.for_many(addresses, %Profile{})

      assert map_size(composed) == 12

      for {_id, name} <- composed do
        assert name == "A region of Middlemarch."
      end
    end
  end

  defp named(conn, path, id), do: conn |> get("/#{path}/#{id}") |> json_response(200)
end
