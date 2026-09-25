defmodule PluteusWeb.AbsenceTest do
  @moduledoc """
  spec-07 criterion 22: every field of a representation carries a value and a
  state, no field is carried by its omission, and a field the deployment cannot
  establish a state for reports *not yet examined*.

  spec-10 criterion 4: a representation carries a value and a state for every
  field, and all seven states of §5.2 are distinguishable in it.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Annotations
  alias Pluteus.Annotations.Annotation
  alias Pluteus.Catalog
  alias Pluteus.Ingest
  alias Pluteus.Principals
  alias Pluteus.Representation.Field

  @envelope ~w(id kind state)

  setup %{conn: conn} do
    {:ok, principal} = Principals.create_principal(%{role: "member"})
    viewer = a_subject()
    {:ok, _} = Principals.bind_identity(principal.id, issuer(), viewer)

    %{conn: through_proxy(conn, viewer), principal: principal}
  end

  describe "22. Every field carries a value and a state, and none is carried by its omission" do
    test "every field of a work, its expression and its manifestation", %{conn: conn} do
      {:ok, catalogued} = Catalog.create_work("The Dig")

      for {kind, path} <- [
            work: "works",
            expression: "expressions",
            manifestation: "manifestations"
          ] do
        body =
          conn
          |> get("/#{path}/#{Map.fetch!(catalogued, kind).id}")
          |> json_response(200)

        assert_every_field_stated(body)
      end
    end

    test "the envelope is not a field, and it is exactly three keys", %{conn: conn} do
      {:ok, %{work: work}} = Catalog.create_work("The Dig")

      body = conn |> get("/works/#{work.id}") |> json_response(200)

      # The identifier, the kind and the lifecycle state are properties of the
      # row's existence rather than things the household may or may not know.
      for key <- @envelope do
        assert is_binary(body[key]), "#{key} is not a plain value"
      end

      assert Enum.sort(Map.keys(body) -- ~w(name nomens categories geometry related own)) ==
               Enum.sort(@envelope)
    end

    test "a field with no value still appears, rather than being left out", %{conn: conn} do
      {:ok, %{work: work}} = Catalog.create_work("The Dig")

      body = conn |> get("/works/#{work.id}") |> json_response(200)

      # Nothing has been recorded about who made it, and the representation says
      # so in the place the answer would have gone.
      assert Map.has_key?(body["related"], "creators")
      assert body["related"]["creators"] == %{"state" => "not_yet_examined"}
      refute Map.has_key?(body["related"]["creators"], "value")
    end

    test "a field the registry does not name reports not yet examined", %{conn: conn} do
      {:ok, %{work: work}} = Catalog.create_work("The Dig")

      body = conn |> get("/works/#{work.id}") |> json_response(200)

      # `parts` is no field an absence may be asserted about, so the deployment
      # cannot establish any of the last three for it, and says the one it can.
      assert body["related"]["parts"]["state"] == "not_yet_examined"
    end

    test "an address carries its whole basis and nothing belonging to another type",
         %{conn: conn} do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("Middlemarch")

      {:ok, %{address: address}} =
        Catalog.create_address(manifestation.id, %{selector_type: :page, page_number: 42})

      body = conn |> get("/addresses/#{address.id}") |> json_response(200)

      assert body["own"]["page_number"] == %{"state" => "held", "value" => 42}
      refute Map.has_key?(body["own"], "start_ms")
      refute Map.has_key?(body["own"], "quote_exact")
    end
  end

  describe "spec-10 criterion 4. All seven states of §5.2 are distinguishable" do
    test "held: a value the household has", %{conn: conn} do
      {:ok, %{work: work}} = Catalog.create_work("The Dig")

      body = conn |> get("/works/#{work.id}") |> json_response(200)

      assert body["name"] == %{"state" => "held", "value" => "The Dig"}
    end

    test "not held: a manifestation the household describes and holds no file for",
         %{conn: conn} do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("The Dig")

      body = conn |> get("/manifestations/#{manifestation.id}") |> json_response(200)

      assert body["related"]["digital_items"] == %{"state" => "not_held"}
    end

    test "not held: a holding whose copies are all lost", %{conn: conn} do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("The Dig")

      {:ok, %{digital_item: digital_item}} =
        Catalog.create_digital_item(manifestation.id, "a rip")

      body = conn |> get("/digital-items/#{digital_item.id}") |> json_response(200)

      assert body["related"]["assets"] == %{"state" => "not_held"}
    end

    test "not yet examined: no tool has looked", %{conn: conn} do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("The Dig")

      body = conn |> get("/manifestations/#{manifestation.id}") |> json_response(200)

      assert body["own"]["loudness"] == %{"state" => "not_yet_examined"}
    end

    test "attempted, failed: a tool looked and could not", %{conn: conn, principal: principal} do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("The Dig")
      {:ok, tool_version} = Annotations.record_tool_version("pluteus-native", "1")

      finding =
        Ingest.record_finding(%{
          stage: :analyse,
          kind: "undecodable",
          permanent: true,
          input_id: manifestation.id,
          tool_version_id: tool_version.id
        })

      body = conn |> get("/manifestations/#{manifestation.id}") |> json_response(200)
      assert body["own"]["loudness"] == %{"state" => "attempted_failed"}

      # Clearing a finding is a person asking for it to be tried again, so the
      # field returns to the state that says nobody has an answer yet.
      {:ok, _cleared} = Ingest.clear_finding(finding.id, principal.id)

      body = conn |> get("/manifestations/#{manifestation.id}") |> json_response(200)
      assert body["own"]["loudness"] == %{"state" => "not_yet_examined"}
    end

    test "sought not found, known unknowable and known absent, each asserted by a person",
         %{conn: conn, principal: principal} do
      for assertion <- Annotation.assertions() do
        {:ok, %{work: work}} = Catalog.create_work("The Dig")

        {:ok, _absence} =
          Annotations.annotate(%{
            target_id: work.id,
            body_type: Annotation.absence(),
            body: %{"field" => "creators", "assertion" => assertion},
            principal_id: principal.id
          })

        body = conn |> get("/works/#{work.id}") |> json_response(200)

        assert body["related"]["creators"] == %{"state" => assertion}
      end
    end

    test "every one of the seven is reachable, and they are all distinct" do
      assert Field.states() == [
               :held,
               :not_held,
               :not_yet_examined,
               :attempted_failed,
               :sought_not_found,
               :known_unknowable,
               :known_absent
             ]

      assert Field.states() == Enum.uniq(Field.states())
      assert :held in Field.states()
      refute :held in Field.absent_states()
    end
  end

  describe "the last three are never inferred from the catalog's silence" do
    test "a work with no creators and no assertion does not claim one was sought",
         %{conn: conn} do
      {:ok, %{work: work}} = Catalog.create_work("The Dig")

      body = conn |> get("/works/#{work.id}") |> json_response(200)

      assert body["related"]["creators"]["state"] == "not_yet_examined"
    end

    test "writing an assertion moves that field and no other", %{
      conn: conn,
      principal: principal
    } do
      {:ok, %{work: work}} = Catalog.create_work("The Dig")

      before = conn |> get("/works/#{work.id}") |> json_response(200)

      {:ok, _absence} =
        Annotations.annotate(%{
          target_id: work.id,
          body_type: Annotation.absence(),
          body: %{"field" => "creators", "assertion" => "known_absent"},
          principal_id: principal.id
        })

      now = conn |> get("/works/#{work.id}") |> json_response(200)

      assert before["related"]["creators"]["state"] == "not_yet_examined"
      assert now["related"]["creators"]["state"] == "known_absent"

      assert Map.delete(before["related"], "creators") ==
               Map.delete(now["related"], "creators")

      assert before["own"] == now["own"]
      assert before["name"] == now["name"]
    end

    test "an assertion outranks a finding, because a tool cannot unsay a person",
         %{conn: conn, principal: principal} do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("The Dig")
      {:ok, tool_version} = Annotations.record_tool_version("pluteus-native", "1")

      Ingest.record_finding(%{
        stage: :analyse,
        kind: "undecodable",
        permanent: true,
        input_id: manifestation.id,
        tool_version_id: tool_version.id
      })

      {:ok, _absence} =
        Annotations.annotate(%{
          target_id: manifestation.id,
          body_type: Annotation.absence(),
          body: %{"field" => "loudness", "assertion" => "known_unknowable"},
          principal_id: principal.id
        })

      body = conn |> get("/manifestations/#{manifestation.id}") |> json_response(200)

      assert body["own"]["loudness"] == %{"state" => "known_unknowable"}
    end
  end

  defp assert_every_field_stated(body) do
    states = Enum.map(Field.states(), &to_string/1)

    fields =
      body
      |> Map.drop(@envelope ++ ~w(related own))
      |> Map.merge(Map.get(body, "related", %{}))
      |> Map.merge(Map.get(body, "own", %{}))

    assert fields != %{}

    for {name, field} <- fields do
      assert is_map(field), "#{name} is not a field: #{inspect(field)}"
      assert field["state"] in states, "#{name} carries no known state"

      case field["state"] do
        "held" -> assert Map.has_key?(field, "value"), "#{name} is held and carries no value"
        _absent -> refute Map.has_key?(field, "value"), "#{name} is absent and carries a value"
      end
    end
  end
end
