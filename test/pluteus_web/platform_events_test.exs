defmodule PluteusWeb.PlatformEventsTest do
  @moduledoc """
  spec-01 §11.2's two classes, and criteria 41 and 42.

  41: a consumption event of one principal is not observable by another through
  any surface; a platform event is observable by every member, including one the
  System principal recorded.

  42: no platform event carries, or can be combined into, what any principal
  consumed.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Events
  alias Pluteus.Events.PlatformEvent
  alias Pluteus.Events.Registry
  alias Pluteus.PlatformEvents
  alias Pluteus.Principals

  setup do
    {:ok, ada} = Principals.create_principal(%{role: "member"})
    {:ok, bo} = Principals.create_principal(%{role: "member"})

    ada_subject = a_subject("ada")
    bo_subject = a_subject("bo")
    {:ok, _} = Principals.bind_identity(ada.id, issuer(), ada_subject)
    {:ok, _} = Principals.bind_identity(bo.id, issuer(), bo_subject)

    %{ada: ada, bo: bo, ada_subject: ada_subject, bo_subject: bo_subject}
  end

  describe "41. A platform event is observable by every member, the System principal's included" do
    test "two members are answered the same events, one of them the System principal's",
         %{conn: conn, ada: ada, ada_subject: ada_subject, bo_subject: bo_subject} do
      {:ok, %{work: work}} = Catalog.create_work("Kind of Blue")
      system = Principals.system!()

      {:ok, _} = PlatformEvents.record("placed", work.id, system.id)
      {:ok, _} = PlatformEvents.record("corrected", work.id, ada.id)

      for subject <- [ada_subject, bo_subject] do
        body =
          conn |> through_proxy(subject) |> get("/platform-events") |> json_response(200)

        events = body["platform_events"]

        assert Enum.sort(Enum.map(events, & &1["type"])) == ["corrected", "placed"]
        assert system.id in Enum.map(events, & &1["recorded_by"])
        assert Enum.all?(events, &(&1["res"] == work.id))
      end
    end

    test "the answer does not depend on who asks", %{conn: conn} = context do
      {:ok, %{work: work}} = Catalog.create_work("Kind of Blue")
      {:ok, _} = PlatformEvents.record("verified", work.id, Principals.system!().id)

      answer = fn subject ->
        conn |> through_proxy(subject) |> get("/platform-events") |> json_response(200)
      end

      assert answer.(context.ada_subject) == answer.(context.bo_subject)
    end

    test "a client key does not reach it", %{conn: conn, ada_subject: ada_subject} do
      minted =
        conn
        |> through_proxy(ada_subject)
        |> post("/devices", %{"label" => "a television"})
        |> json_response(201)

      assert conn
             |> via_proxy()
             |> get("/platform-events", %{"apiKey" => minted["key"]})
             |> response(401)
    end
  end

  describe "41, the other half. One principal's consumption is not observable by another" do
    test "a play by one member is in neither member's platform events",
         %{conn: conn, ada: ada, ada_subject: ada_subject, bo_subject: bo_subject} do
      {:ok, %{work: work}} = Catalog.create_work("Kind of Blue")
      {:ok, _} = Events.record(ada.id, work.id, "played")

      for subject <- [ada_subject, bo_subject] do
        body = conn |> through_proxy(subject) |> get("/platform-events") |> json_response(200)
        assert body["platform_events"] == []
      end
    end

    test "and is not in the other member's own events", %{ada: ada, bo: bo} do
      {:ok, %{work: work}} = Catalog.create_work("Kind of Blue")
      {:ok, _} = Events.record(ada.id, work.id, "played")

      assert Events.for_principal(bo.id) == []
      assert [%{type: "played"}] = Events.for_principal(ada.id)
    end
  end

  describe "§11.3's platform types, and which of them this deployment records" do
    test "a member correcting a category produces a household-visible event",
         %{conn: conn, ada: ada, ada_subject: ada_subject, bo_subject: bo_subject} do
      {:ok, %{work: work}} = Catalog.create_work("Kind of Blue")

      conn
      |> through_proxy(ada_subject)
      |> post("/works/#{work.id}/categories", %{"scheme" => "genre", "value" => "Jazz"})
      |> json_response(201)

      # §11.2: the class is decided by what the event records and not by who acted,
      # so a member's correction is a platform event and the household sees it —
      # including Bo, who did not make it.
      body = conn |> through_proxy(bo_subject) |> get("/platform-events") |> json_response(200)

      assert [%{"type" => "corrected", "res" => res, "recorded_by" => by}] =
               body["platform_events"]

      assert res == work.id
      assert by == ada.id
    end

    test "the types this deployment records, and the two it does not" do
      # A ledger rather than an introspection: each of these four is asserted where
      # its own machinery is tested. It fails if a recorder is added without moving
      # a name across, or if a type is added to the registry without deciding.
      #
      # `matched` is spec-05 §8's and waits with it. `acquired` is §11.1's "a file
      # arriving", which happens before any res exists — and `platform_events.res_id`
      # is NOT NULL, so recording one is a schema question rather than a call.
      recorded = ~w(placed normalized verified corrected)

      assert Registry.types(:platform) -- recorded == ~w(acquired matched)
    end
  end

  describe "42. No platform event carries, or can be combined into, what anyone consumed" do
    test "the table has no column that could scope a row to a principal" do
      # The guarantee is the shape of the table rather than a rule a writer keeps:
      # `recorded_by` is who acted, which §11.2 says does not decide the class and
      # §6.4 requires be visible, and there is nothing else to combine.
      assert PlatformEvent.__schema__(:fields) == [
               :id,
               :type,
               :res_id,
               :recorded_by,
               :occurred_at,
               :inserted_at,
               :updated_at
             ]

      refute :principal_id in PlatformEvent.__schema__(:fields)
    end

    test "the module answers without being told who is asking" do
      # The counterpart of the closed list asserted for `Pluteus.Events`, whose every
      # read takes its principal first. Adding a read here that takes one is how §11.2
      # would be violated from this side.
      exported = Pluteus.PlatformEvents.__info__(:functions) |> Enum.sort()

      assert exported == [about: 1, all: 0, all: 1, record: 3, record: 4]
    end

    test "a platform event about the very res a principal played still names no consumer",
         %{conn: conn, ada: ada, ada_subject: ada_subject, bo_subject: bo_subject} do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("Kind of Blue")

      # The hard case for the criterion: the platform event and the consumption
      # event are about the same res, so sharing a res is not what keeps them apart.
      {:ok, _} = PlatformEvents.record("placed", manifestation.id, Principals.system!().id)
      {:ok, _} = Events.record(ada.id, manifestation.id, "played")

      body = conn |> through_proxy(bo_subject) |> get("/platform-events") |> json_response(200)

      assert [placed] = body["platform_events"]
      assert placed["res"] == manifestation.id

      # What keeps them apart is that the row names who acted and no one else. Bo
      # learns the manifestation was placed, and by the System principal, and
      # nothing about anybody playing it.
      assert placed["recorded_by"] == Principals.system!().id
      assert Map.keys(placed) == ~w(id occurred_at recorded_by res type)

      # Ada's answer is the same answer, so a member cannot read their own
      # consumption back out of it either, and Bo's cannot differ from it.
      assert conn |> through_proxy(ada_subject) |> get("/platform-events") |> json_response(200) ==
               body
    end
  end
end
