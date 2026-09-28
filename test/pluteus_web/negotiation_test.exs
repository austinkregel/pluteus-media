defmodule PluteusWeb.NegotiationTest do
  @moduledoc """
  One address, two representations: spec-07 §4.1 and criterion 24, spec-10 §10.1 and
  §9.1.

  §4.1 negotiates on the presence of `text/html` and not on a preference list, so most of
  what is asserted here is what does *not* answer with the interface.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Representation.ComposedName
  alias Pluteus.Representation.Field
  alias PluteusWeb.EntityLive
  alias PluteusWeb.Native
  alias PluteusWeb.Surface

  @subject "ada@example.test"

  setup %{conn: conn} do
    {:ok, %{work: work, expression: expression}} = Catalog.create_work("Kind of Blue")

    %{
      conn: conn |> through_proxy(@subject) |> on_a_surface(),
      work: work,
      expression: expression
    }
  end

  defp asking(conn), do: conn |> through_proxy(@subject) |> put_req_header("accept", "text/html")

  describe "spec-07 criterion 24. text/html answers the interface" do
    test "a header containing text/html renders it", %{conn: conn, work: work} do
      html =
        conn
        |> put_req_header("accept", "text/html")
        |> get("/works/#{work.id}")
        |> html_response(200)

      assert html =~ "Kind of Blue"
    end

    test "presence decides, not preference", %{conn: conn, work: work} do
      # A client naming JSON first and HTML at q=0.1 has still named text/html. §4.1 makes
      # that the whole test, so a quality ordering cannot change the answer.
      assert conn
             |> put_req_header("accept", "application/json, text/html;q=0.1")
             |> get("/works/#{work.id}")
             |> html_response(200) =~ "Kind of Blue"
    end

    test "a header of */* answers the representation, unchanged", %{conn: conn, work: work} do
      bare = conn |> get("/works/#{work.id}") |> json_response(200)

      wildcard =
        build_conn()
        |> through_proxy(@subject)
        |> on_a_surface()
        |> put_req_header("accept", "*/*")
        |> get("/works/#{work.id}")
        |> json_response(200)

      assert wildcard == bare
    end

    test "text/* is not text/html", %{conn: conn, work: work} do
      assert conn
             |> put_req_header("accept", "text/*")
             |> get("/works/#{work.id}")
             |> json_response(200)
    end

    test "_format=html is honoured where a client cannot set its header", %{
      conn: conn,
      work: work
    } do
      assert conn |> get("/works/#{work.id}", %{"_format" => "html"}) |> html_response(200) =~
               "Kind of Blue"
    end

    test "a parameter naming no selector dimension reaches the deep link as nothing", %{
      conn: conn,
      expression: expression
    } do
      # §4.1 requires a selector parser ignore it, so `_format` must not make the request
      # malformed the way an unreadable selector would.
      assert conn
             |> get("/expressions/#{expression.id}", %{"_format" => "html"})
             |> html_response(200)
    end
  end

  describe "spec-10 §9.1. Which kinds have an interface page" do
    test "the kinds that negotiate are the ones §9.1 names" do
      # §9.1's list, with both kinds of agent counted.
      negotiating = Native.paths() |> Map.keys() |> Enum.filter(&Native.negotiates?/1)

      assert Enum.sort(negotiating) ==
               ~w(address collective_agent digital_item expression item
                  manifestation person place time_span work)a
    end

    test "a nomen answers the representation though the request asked for the interface", %{
      conn: conn,
      work: work
    } do
      # A nomen is one of the three §9.1 excludes. It stays reachable as JSON whatever was
      # asked for.
      %{"nomens" => %{"value" => [nomen | _rest]}} =
        conn |> get("/works/#{work.id}") |> json_response(200)

      assert build_conn()
             |> through_proxy(@subject)
             |> put_req_header("accept", "text/html")
             |> get("/nomens/#{nomen["id"]}")
             |> json_response(200)
    end

    test "every kind either negotiates or is one of the three §9.1 excludes" do
      excluded = for kind <- Map.keys(Native.paths()), not Native.negotiates?(kind), do: kind

      assert Enum.sort(excluded) == ~w(annotation asset nomen)a
    end
  end

  describe "spec-10 §10.1. One address" do
    test "a refusal is the same refusal whatever was asked for" do
      # Only the live branch forks, so an identifier that names nothing is 404 and carries
      # the problem document rather than an interface saying nothing.
      for accept <- ["text/html", "application/json"] do
        conn =
          build_conn()
          |> through_proxy(@subject)
          |> put_req_header("accept", accept)
          |> get("/works/#{Ecto.UUID.generate()}")

        assert conn.status == 404
      end
    end

    test "a malformed selector is refused before the interface is reached", %{
      conn: conn,
      expression: expression
    } do
      conn =
        conn
        |> put_req_header("accept", "text/html")
        |> get("/expressions/#{expression.id}", %{"t" => "npt:not-a-time"})

      assert conn.status == 400
    end
  end

  describe "spec-10 §4.4. A surface is declared and is not inferred" do
    test "an undetermined surface is asked about before anything is rendered", %{work: work} do
      # §4.4 leaves an undeclared surface undetermined and has the deployment ask rather
      # than choose.
      conn = build_conn() |> asking() |> get("/works/#{work.id}")

      assert redirected_to(conn) == "/surface?return_to=%2Fworks%2F#{work.id}"
    end

    test "a cookie naming no context it admits is no declaration", %{work: work} do
      conn = build_conn() |> asking() |> on_a_surface("three metres") |> get("/works/#{work.id}")

      assert conn.status == 302
    end

    test "the representation is served whether or not a surface is declared", %{work: work} do
      # The declaration governs how something is drawn, so it has nothing to say about a
      # request that asked for the representation.
      assert build_conn()
             |> through_proxy(@subject)
             |> get("/works/#{work.id}")
             |> json_response(200)
    end

    test "the question offers every context and nothing else", %{conn: conn} do
      html = conn |> get("/surface") |> html_response(200)

      for distance <- Surface.contexts() do
        assert html =~ ~s(value="#{distance}")
        assert html =~ ~s(id="surface-#{distance}")
      end
    end

    test "answering records the declaration and returns where the person was going", %{
      conn: conn,
      work: work
    } do
      conn = post(conn, "/surface", %{"distance" => "far", "return_to" => "/works/#{work.id}"})

      assert redirected_to(conn) == "/works/#{work.id}"
      assert conn.resp_cookies[Surface.cookie()].value == "far"
    end

    test "a return_to naming somewhere else is not followed", %{conn: conn} do
      # A question that sends someone off this deployment on being answered is an open
      # redirect.
      conn = post(conn, "/surface", %{"distance" => "near", "return_to" => "//example.test/x"})

      assert redirected_to(conn) == "/example.test/x"
    end

    test "a declared surface reaches the document root", %{conn: conn, work: work} do
      html = conn |> on_a_surface("far") |> asking() |> get("/works/#{work.id}")
      html = html_response(html, 200)

      assert html =~ ~s(data-distance="far")
      assert html =~ ~s(data-declared="distance")
    end

    test "the script names no default for the surface", %{conn: conn} do
      # A default in the script is the interface choosing a surface, which §4.4 forbids.
      html = conn |> get("/") |> html_response(200)

      refute html =~ "distance: \"near\""
      refute html =~ "distance: \"far\""
    end
  end

  describe "spec-10 §8.4. The page's bands" do
    test "band 1 says what kind of thing this is, and not in the model's words", %{
      conn: conn,
      work: work
    } do
      html = conn |> put_req_header("accept", "text/html") |> get("/works/#{work.id}")
      html = html_response(html, 200)

      # §8.5 forbids the model's vocabulary as a heading or a label. The noun comes from
      # `ComposedName`, which is where the interface's own words for a kind live.
      assert html =~ ComposedName.noun(:work)
    end

    test "an absent field is said in words where its value would have gone", %{
      conn: conn,
      expression: expression
    } do
      # §5.1: the catalog is mostly holes, and §5.2 requires a surface distinguish the
      # eight states. Rendering an absence as emptiness is what reaches assistive
      # technology as nothing at all.
      html =
        conn
        |> put_req_header("accept", "text/html")
        |> get("/expressions/#{expression.id}")
        |> html_response(200)

      assert html =~ "not yet examined"
    end

    test "the live region is rendered and empty", %{conn: conn, work: work} do
      html =
        conn
        |> put_req_header("accept", "text/html")
        |> get("/works/#{work.id}")
        |> html_response(200)

      assert html =~ ~s(role="status")
      assert html =~ ~s(aria-live="polite")
      assert html =~ ~r/id="entity-announcement"[^>]*>\s*<\/div>/
    end

    test "every link carries a stable identity derived from what it points at", %{
      conn: conn,
      work: work,
      expression: expression
    } do
      # §17.7 requires it, because LiveView protects only a focused form input from a
      # patch: a focused link is neither protected nor restored.
      html =
        conn
        |> put_req_header("accept", "text/html")
        |> get("/works/#{work.id}")
        |> html_response(200)

      assert html =~ ~s(id="entity-link-#{expression.id}")
      assert html =~ ~s(href="/expressions/#{expression.id}")
    end

    test "every absent state has words of its own" do
      # §5.2 requires a surface distinguish all of them, so no two share a phrase and none
      # is left without one. A state with no words raises here rather than rendering as
      # emptiness on the page.
      said =
        for state <- Field.absent_states(), do: EntityLive.absence(to_string(state))

      assert length(said) == length(Field.absent_states())
      assert length(Enum.uniq(said)) == length(said)
    end
  end
end
