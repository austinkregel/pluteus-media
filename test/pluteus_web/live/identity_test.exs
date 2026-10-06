defmodule PluteusWeb.Live.IdentityTest do
  @moduledoc """
  The principal a LiveView renders for, on both of its mounts.

  A LiveView has two mounts with different evidence: the dead render carries the
  principal the request established, and the socket's only identity is the proxy's
  headers. spec-10 §14.3 forbids a surface composed from more than one principal, so
  the two agreeing is not an invariant to assume — it is one to raise on.
  """

  use PluteusWeb.ConnCase, async: true

  # Two of these provoke the raise on purpose, and the mount crashing is what they
  # assert. The message is asserted from the exit, so the same message logged beside it
  # reads as a failure the run did not have.
  @moduletag capture_log: true

  alias Pluteus.Catalog

  @subject "ada@example.test"
  @other "grace@example.test"

  setup %{conn: conn} do
    {:ok, %{work: work}} = Catalog.create_work("Kind of Blue")

    %{conn: conn |> through_proxy(@subject) |> on_a_surface(), work: work}
  end

  describe "A rendered entity page can be joined" do
    test "the page carries a forgery token the session can verify", %{conn: conn, work: work} do
      # Without one the join is refused as misconfigured, and the client recovers by
      # reloading the page — which lands here again and reloads again, for as long as it
      # is open. The pipeline this page renders from cannot carry the plug, because it
      # also serves the writes the plug would start refusing.
      conn = conn |> asking() |> get("/works/#{work.id}")

      assert html_response(conn, 200) =~ "csrf-token"
      assert Plug.Conn.get_session(conn, "_csrf_token")
    end
  end

  describe "spec-10 §14.3. One page, one principal" do
    test "the connected mount establishes the principal from the socket", %{
      conn: conn,
      work: work
    } do
      # The harness derives the socket's x- headers from the connection the dead render
      # was made with, so this exercises the header branch and not the session's.
      {:ok, _view, html} = conn |> asking() |> get("/works/#{work.id}") |> live()

      assert html =~ "Kind of Blue"
    end

    test "a socket naming another principal is refused", %{conn: conn, work: work} do
      message =
        conn |> asking() |> on_a_socket_as(@other) |> get("/works/#{work.id}") |> refused()

      assert message =~ "the socket is"
      assert message =~ "and the page is"
    end

    test "a socket carrying no principal is refused", %{conn: conn, work: work} do
      # An empty header set is not an anonymous mount. The dead render reached this page
      # through forward authentication, so a socket that cannot produce the same
      # principal is a socket this page must not be driven over.
      conn =
        conn
        |> asking()
        |> Plug.Conn.put_private(:live_view_connect_info, Phoenix.ConnTest.build_conn())
        |> get("/works/#{work.id}")

      assert refused(conn) =~ "the socket carries no principal"
    end

    test "the dead render stands on the session alone", %{conn: conn, work: work} do
      # A dead render has no connect info at all, which is why the hook has a clause for
      # its absence rather than treating it as a socket that failed to identify.
      assert conn |> asking() |> get("/works/#{work.id}") |> html_response(200) =~ "Kind of Blue"
    end
  end

  defp asking(conn), do: put_req_header(conn, "accept", "text/html")

  # The mount raises inside the LiveView's own process, so the connect exits rather than
  # raising here. The message is what the assertion is about: a refusal that named the
  # wrong reason would pass a looser check.
  defp refused(conn) do
    {{%RuntimeError{message: message}, _stacktrace}, _call} = catch_exit(live(conn))

    message
  end
end
