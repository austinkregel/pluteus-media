defmodule PluteusWeb.PreferencesApiTest do
  @moduledoc """
  spec-07 §4.1's preferences resource, and the confidentiality spec-10 §14.5 requires
  of what it carries.

  §14.5: a principal's presentation preferences "MUST NOT be visible to another".
  §21: they "are per principal and are not household-visible". The resource keeps
  that by carrying no principal identifier, so what is asserted here is that there is
  no request which reaches another's — not that one is refused.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Preferences.Registry

  @ada "ada@example.test"
  @grace "grace@example.test"

  describe "spec-07 §4.1. The principal's own preferences" do
    test "every key is answered, defaulted where nothing is set", %{conn: conn} do
      body = conn |> through_proxy(@ada) |> get("/preferences") |> json_response(200)

      assert body["preferences"] == Registry.defaults()

      for key <- Registry.keys() do
        assert Map.has_key?(body["preferences"], key),
               "#{key} is settable and is not answered, so a client cannot show it"
      end
    end

    test "a set is written and answered back whole", %{conn: conn} do
      body =
        conn
        |> through_proxy(@ada)
        |> put("/preferences", %{"preferences" => %{"motion" => "reduced", "theme" => "light"}})
        |> json_response(200)

      assert body["preferences"]["motion"] == "reduced"
      assert body["preferences"]["theme"] == "light"
      assert body["preferences"]["density"] == Registry.default("density")
    end

    test "a caption property and a browse mode are settable over the wire", %{conn: conn} do
      # §17.4 requires caption presentation be adjustable by the person; §9.2 permits a
      # mode be hidden. Both are reachable here or they are not adjustable at all.
      body =
        conn
        |> through_proxy(@ada)
        |> put("/preferences", %{
          "preferences" => %{"caption_ground" => "none", "browse_people" => "hidden"}
        })
        |> json_response(200)

      assert body["preferences"]["caption_ground"] == "none"
      assert body["preferences"]["browse_people"] == "hidden"
    end
  end

  describe "spec-10 §14.5. Not visible to another" do
    test "one principal's preferences do not appear in another's answer", %{conn: conn} do
      conn
      |> through_proxy(@ada)
      |> put("/preferences", %{"preferences" => %{"motion" => "reduced"}})
      |> json_response(200)

      body = build_conn() |> through_proxy(@grace) |> get("/preferences") |> json_response(200)

      assert body["preferences"]["motion"] == Registry.default("motion")
    end

    test "no route names a principal, so no request asks for another's" do
      # spec-07 §4.5 makes a refusal a disclosure — a 403 "would confirm that another
      # principal's datum exists". The resource is shaped so the question has no form.
      preference_routes =
        PluteusWeb.Router.__routes__()
        |> Enum.filter(&String.starts_with?(&1.path, "/preferences"))

      assert preference_routes != []

      for route <- preference_routes do
        assert route.path == "/preferences"
        refute route.path =~ ":"
      end
    end
  end

  describe "spec-07 §4.5. Refusals" do
    test "an unknown key is 400 and names itself", %{conn: conn} do
      body =
        conn
        |> through_proxy(@ada)
        |> put("/preferences", %{"preferences" => %{"favourite_colour" => "blue"}})
        |> json_response(400)

      assert body["title"] == "invalid-request"
      assert body["detail"] =~ "favourite_colour"
    end

    test "a value outside its domain is 422 and names the domain", %{conn: conn} do
      body =
        conn
        |> through_proxy(@ada)
        |> put("/preferences", %{"preferences" => %{"motion" => "sideways"}})
        |> json_response(422)

      assert body["title"] == "constraint"
      assert body["preference"] == "motion"
      assert body["admits"]["values"] == ["system", "full", "reduced"]
    end

    test "one bad value leaves the rest of the set unwritten", %{conn: conn} do
      conn
      |> through_proxy(@ada)
      |> put("/preferences", %{"preferences" => %{"theme" => "light", "motion" => "sideways"}})
      |> json_response(422)

      body = build_conn() |> through_proxy(@ada) |> get("/preferences") |> json_response(200)

      assert body["preferences"]["theme"] == Registry.default("theme")
    end

    test "a body naming nothing to set is 400", %{conn: conn} do
      body =
        conn
        |> through_proxy(@ada)
        |> put("/preferences", %{"preferences" => %{}})
        |> json_response(400)

      assert body["title"] == "invalid-request"
    end
  end

  describe "spec-07 §3.4. Not reachable by a client key" do
    test "the resource is behind forward authentication", %{conn: conn} do
      # The `:api` pipeline is what carries it, so a request without the proxy's
      # header is refused before the controller is reached.
      assert conn |> get("/preferences") |> json_response(401)
    end
  end
end
