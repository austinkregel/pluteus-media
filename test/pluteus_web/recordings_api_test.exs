defmodule PluteusWeb.RecordingsApiTest do
  @moduledoc """
  The two writes that let a person say how a household's recordings of one song relate
  (spec-07 §4.3): recording what kind of recording each is, and proposing that two are
  the same song so that a *same work* decision can bring them under one work.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Expression
  alias Pluteus.Ingest.Place
  alias Pluteus.Repo

  setup %{conn: conn} do
    %{conn: through_proxy(conn, a_subject())}
  end

  describe "spec-07 §4.3. An attributes write revises what it names" do
    test "an expression's performance is recorded and its other attributes kept",
         %{conn: conn} do
      %{expression: expression} = a_song("Iron Fist")

      conn
      |> post("/expressions/#{expression.id}/attributes", %{attributes: %{key: "E minor"}})
      |> json_response(200)

      body =
        conn
        |> post("/expressions/#{expression.id}/attributes", %{
          attributes: %{performance: "live"}
        })
        |> json_response(200)

      assert body == %{
               "id" => expression.id,
               "attributes" => %{"key" => "E minor", "performance" => "live"}
             }
    end

    test "a work's representative performance is recorded the same way", %{conn: conn} do
      %{work: work} = a_song("Iron Fist")

      body =
        conn
        |> post("/works/#{work.id}/attributes", %{attributes: %{performance: "studio"}})
        |> json_response(200)

      assert body["attributes"] == %{"performance" => "studio"}
    end

    test "a value outside the vocabulary is refused naming the vocabulary", %{conn: conn} do
      %{expression: expression} = a_song("Iron Fist")

      body =
        conn
        |> post("/expressions/#{expression.id}/attributes", %{
          attributes: %{performance: "bootleg"}
        })
        |> json_response(422)

      assert inspect(body["detail"]) =~ "studio, live, demo, remix, alternate"
    end

    test "a request naming no attributes object is refused", %{conn: conn} do
      %{expression: expression} = a_song("Iron Fist")

      assert conn
             |> post("/expressions/#{expression.id}/attributes", %{performance: "live"})
             |> json_response(400)
    end
  end

  describe "spec-07 §4.3. A member proposes that two recordings are one song" do
    test "and a same-work decision brings them under one work", %{conn: conn} do
      %{manifestation: studio, expression: studio_recording} = a_song("The Afterman")
      %{manifestation: demo, expression: demo_recording} = a_song("The Afterman (demo)")

      proposal =
        conn
        |> post("/duplicate-candidates", %{left_id: demo.id, right_id: studio.id})
        |> json_response(200)

      assert proposal["signal"] == "member"

      conn
      |> post("/duplicate-candidates/#{proposal["id"]}/decision", %{decision: "same_work"})
      |> json_response(200)

      works =
        [studio_recording.id, demo_recording.id]
        |> Enum.map(&Repo.get!(Expression, &1).work_id)
        |> Enum.uniq()

      assert [_one] = works
    end

    test "a pair of works is refused, since no decision could resolve it", %{conn: conn} do
      %{work: one} = a_song("Iron Fist")
      %{work: other} = a_song("Iron Fist (demo)")

      body =
        conn
        |> post("/duplicate-candidates", %{left_id: one.id, right_id: other.id})
        |> json_response(422)

      assert inspect(body["detail"]) =~ "not_a_holding"
    end

    test "a pair already decided is refused rather than raised again", %{conn: conn} do
      %{manifestation: one} = a_song("Iron Fist")
      %{manifestation: other} = a_song("Iron Fist (acoustic stripped demo)")

      proposal =
        conn
        |> post("/duplicate-candidates", %{left_id: one.id, right_id: other.id})
        |> json_response(200)

      conn
      |> post("/duplicate-candidates/#{proposal["id"]}/decision", %{decision: "distinct"})
      |> json_response(200)

      body =
        conn
        |> post("/duplicate-candidates", %{left_id: other.id, right_id: one.id})
        |> json_response(422)

      assert inspect(body["detail"]) =~ "already_decided"
    end

    test "a request naming only one of the pair is refused", %{conn: conn} do
      %{manifestation: one} = a_song("Iron Fist")

      assert conn |> post("/duplicate-candidates", %{left_id: one.id}) |> json_response(400)
    end
  end

  defp a_song(name) do
    {:ok, %{work: work} = created} = Catalog.create_work(name)

    {:ok, _} =
      Catalog.categorize(work.id, Place.category_scheme(), "music_recording", :automatic)

    created
  end
end
