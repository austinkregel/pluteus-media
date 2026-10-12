defmodule PluteusWeb.FindingsLiveTest do
  @moduledoc """
  The findings surface ([spec-10] §16.1), and the vocabulary it carries.

  §16.1 puts a failure where it can be seen rather than in a log, and §5.2 fixes what a
  surface may say about a value that is not there. The vocabulary is on this surface
  because this is where a person comes when something is not as they expected, and the
  difference between *nobody looked* and *a tool tried and could not* is the difference
  between waiting and acting.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Ingest
  alias Pluteus.Principals
  alias PluteusWeb.Absence

  setup %{conn: conn} do
    _system = Principals.system!()

    # §4.1 forks this address on what was asked for, and `*/*` is not HTML: without the
    # header the request is answered as the representation and there is no session.
    conn =
      conn
      |> through_proxy(a_subject())
      |> on_a_surface()
      |> Plug.Conn.put_req_header("accept", "text/html")

    %{conn: conn}
  end

  describe "§16.1. A failure reaches a person" do
    test "a finding is listed, grouped by what went wrong", %{conn: conn} do
      recorded("text_is_not_utf8")

      {:ok, _live, html} = live(conn, ~p"/findings")

      assert html =~ "text_is_not_utf8"
      assert html =~ "1 is uncleared"
    end

    test "nothing outstanding says so", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/findings")

      assert html =~ "Nothing is outstanding."
    end
  end

  describe "§5.2. Eight states, and no surface renders two of them alike" do
    test "every state is in the vocabulary, with the words it is said in", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/findings")

      assert html =~ ~s|id="findings-vocabulary"|

      for state <- Absence.states() do
        assert html =~ Absence.words(state),
               "#{state} is a state a surface may report and the vocabulary omits it"
      end

      # The eighth is the value being there, which A.8.8 gives no marker precisely so
      # that nothing stands for it.
      assert html =~ "held"
    end
  end

  # A finding names what it is about, which the database holds it to: this one is about
  # bytes at a location, which is the subject a stray-byte finding carries.
  defp recorded(kind) do
    Ingest.record_finding(%{
      stage: :normalize,
      kind: kind,
      permanent: false,
      detail: %{},
      location: "a6/89/#{Ecto.UUID.generate()}",
      recorded_at: DateTime.utc_now()
    })
  end
end
