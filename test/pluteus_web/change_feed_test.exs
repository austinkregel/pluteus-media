defmodule PluteusWeb.ChangeFeedTest do
  @moduledoc """
  The change feed and the socket's pushes: spec-07 §5 and criteria 11 to 13.

  What is tested here is how writes in separate transactions commit relative
  to one another, which a sandbox's one uncommitted transaction cannot show.
  These tests commit, so they run with no other test alongside, and remove what
  they wrote.
  """

  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]
  import Phoenix.ChannelTest
  import Phoenix.ConnTest, only: [build_conn: 0, get: 3, json_response: 2]
  import PluteusWeb.ConnCase, only: [through_proxy: 2, issuer: 0]

  alias Ecto.Adapters.SQL.Sandbox
  alias Phoenix.Socket.Message
  alias Pluteus.Actor
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Category
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Extent
  alias Pluteus.Catalog.Manifestation
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Res
  alias Pluteus.Catalog.Work
  alias Pluteus.Changes.Release
  alias Pluteus.Consumption
  alias Pluteus.ConsumptionFixtures
  alias Pluteus.Principals
  alias Pluteus.Repo
  alias PluteusWeb.CatalogChannel
  alias PluteusWeb.ClientSocket
  alias PluteusWeb.PrincipalChannel

  @endpoint PluteusWeb.Endpoint
  @interval 20

  setup do
    :ok = Sandbox.mode(Repo, :auto)
    subject = "feed-#{System.unique_integer([:positive])}@example.test"
    principal = Principals.admit(issuer(), subject)
    start_supervised!({Release, interval: @interval})

    on_exit(fn -> remove(principal.id) end)

    %{conn: through_proxy(build_conn(), subject), subject: subject, principal: principal}
  end

  describe "11. The feed never releases a write before every lower-numbered one ends" do
    test "a committed write waits for a lower-numbered one in flight to commit",
         %{conn: conn, principal: principal} do
      start = caught_up()
      held = hold_open(principal.id)
      assert_receive {:holding, low}

      high = write!(principal.id)
      assert high > low

      Process.sleep(@interval * 10)
      assert Release.released() < low
      refute high in numbers(conn, start)

      finish(held, :commit)
      wait_for_release(high)
      assert numbers(conn, start) == [low, high]
    end

    test "a committed write waits for a lower-numbered one in flight to fail",
         %{conn: conn, principal: principal} do
      start = caught_up()
      held = hold_open(principal.id)
      assert_receive {:holding, low}

      high = write!(principal.id)

      Process.sleep(@interval * 10)
      assert Release.released() < low

      finish(held, :rollback)
      wait_for_release(high)
      assert numbers(conn, start) == [high]
    end

    test "each entry is its number, the operation and the res it touched",
         %{conn: conn, principal: principal} do
      start = caught_up()

      {:ok, %{res: res}} =
        Actor.as(principal.id, fn -> Catalog.create_named_res(:time_span, "1959") end)

      wait_for_release(allocated())

      body = conn |> get("/changes", %{"after" => to_string(start)}) |> json_response(200)

      entry = Enum.find(body["changes"], &(&1["res"] == [res.id]))

      assert %{"number" => number, "operation" => "insert"} = entry
      assert number > start and body["released"] >= number
      assert Enum.map(body["changes"], & &1["number"]) == Enum.sort(numbers(conn, start))
    end

    test "an after that is not a number is refused", %{conn: conn} do
      assert conn |> get("/changes", %{"after" => "-1"}) |> json_response(400)
      assert conn |> get("/changes", %{"after" => "soon"}) |> json_response(400)
    end
  end

  describe "12. The socket pushes feed numbers and no rows" do
    test "a push is the released number alone, and the feed recovers a gap",
         %{conn: conn, subject: subject, principal: principal} do
      caught_up()
      {:ok, socket} = connect_as(subject)

      {:ok, %{"released" => joined_at}, channel} =
        subscribe_and_join(socket, CatalogChannel, "catalog")

      first = write!(principal.id)
      wait_for_release(first)
      assert_push "released", %{"number" => pushed} = payload, 1_000
      assert Map.keys(payload) == ["number"]
      assert pushed >= first

      Process.unlink(channel.channel_pid)
      :ok = close(channel)
      missed = [write!(principal.id), write!(principal.id)]
      wait_for_release(List.last(missed))

      assert numbers(conn, pushed) == missed
      assert joined_at < first
    end
  end

  describe "13. A principal's consumption notice reaches that principal's topic alone" do
    test "a resume position set by one principal is announced to it and no other",
         %{subject: subject, principal: principal} do
      other = Principals.admit(issuer(), "other-" <> subject)
      on_exit(fn -> remove(other.id) end)

      own_topic = "principal:#{principal.id}"
      other_topic = "principal:#{other.id}"
      {:ok, own} = connect_as(subject)
      {:ok, _reply, _channel} = subscribe_and_join(own, PrincipalChannel, own_topic)
      {:ok, theirs} = connect_as("other-" <> subject)
      {:ok, _reply, _channel} = subscribe_and_join(theirs, PrincipalChannel, other_topic)

      # A position is weighed against its category ([spec-10] §13.2), so it is
      # reported against a categorized work rather than a bare res.
      resumable =
        Actor.as(principal.id, fn -> ConsumptionFixtures.resumable_work!(principal.id) end)

      ConsumptionFixtures.position!(principal.id, resumable.work.id, resumable.device.id)

      assert_receive %Message{topic: ^own_topic, event: "changed", payload: payload}, 1_000
      assert payload == %{"data" => "resume_positions"}
      refute_receive %Message{topic: ^other_topic}, @interval * 10
    end

    test "each kind of consumption data is announced as itself", %{
      subject: subject,
      principal: principal
    } do
      own_topic = "principal:#{principal.id}"
      {:ok, own} = connect_as(subject)
      {:ok, _reply, _channel} = subscribe_and_join(own, PrincipalChannel, own_topic)

      {:ok, %{res: res}} =
        Actor.as(principal.id, fn -> Catalog.create_named_res(:time_span, "1959") end)

      {:ok, _} = Consumption.star(principal.id, res.id)
      {:ok, _} = Consumption.rate(principal.id, res.id, 4)
      {:ok, playlist} = Consumption.create_playlist(principal.id, "Evening", [])
      {:ok, _} = Consumption.update_playlist(principal.id, playlist.id, %{append: [res.id]})
      {:ok, phone} = Principals.bind_device(principal.id, "phone")
      {:ok, _} = Consumption.save_play_queue(principal.id, [res.id], 0, 0, phone.id)
      :ok = Consumption.playing(principal.id, phone.id, res.id)
      {:ok, _} = Consumption.played(principal.id, phone.id, res.id)

      for data <- ~w(stars ratings playlists playlists play_queues now_playing events now_playing) do
        assert_receive %Message{topic: ^own_topic, event: "changed", payload: %{"data" => ^data}},
                       1_000
      end
    end

    test "a change rolled back is never announced", %{subject: subject, principal: principal} do
      own_topic = "principal:#{principal.id}"
      {:ok, own} = connect_as(subject)
      {:ok, _reply, _channel} = subscribe_and_join(own, PrincipalChannel, own_topic)

      resumable =
        Actor.as(principal.id, fn -> ConsumptionFixtures.resumable_work!(principal.id) end)

      {:error, :abandoned} =
        Repo.transaction(fn ->
          ConsumptionFixtures.position!(principal.id, resumable.work.id, resumable.device.id)
          Repo.rollback(:abandoned)
        end)

      refute_receive %Message{topic: ^own_topic}, @interval * 10
    end
  end

  # Every write so far released, so a test's own writes are the ones after.
  defp caught_up do
    number = allocated()
    wait_for_release(number)
    number
  end

  defp allocated do
    [[number]] =
      Repo.query!(
        "SELECT CASE WHEN is_called THEN last_value ELSE 0 END FROM catalog_writes_id_seq"
      ).rows

    number
  end

  defp wait_for_release(number, tries \\ 200) do
    cond do
      Release.released() >= number -> :ok
      tries == 0 -> flunk("write #{number} was never released")
      true -> wait_again(number, tries)
    end
  end

  defp wait_again(number, tries) do
    Process.sleep(@interval)
    wait_for_release(number, tries - 1)
  end

  defp numbers(conn, after_number) do
    conn
    |> get("/changes", %{"after" => to_string(after_number), "limit" => "500"})
    |> json_response(200)
    |> Map.fetch!("changes")
    |> Enum.map(& &1["number"])
  end

  defp write!(principal_id) do
    [[number]] =
      Repo.query!(
        """
        INSERT INTO catalog_writes (principal_id, table_name, operation, row_key, res_ids, occurred_at)
          VALUES ($1, 'res', 'UPDATE', '{}', '{}', clock_timestamp()) RETURNING id
        """,
        [Ecto.UUID.dump!(principal_id)]
      ).rows

    number
  end

  defp hold_open(principal_id) do
    parent = self()

    Task.async(fn ->
      Repo.transaction(fn ->
        send(parent, {:holding, write!(principal_id)})

        receive do
          :commit -> :ok
          :rollback -> Repo.rollback(:abandoned)
        end
      end)
    end)
  end

  defp finish(task, outcome) do
    send(task.pid, outcome)
    Task.await(task)
  end

  defp connect_as(subject) do
    config = Application.fetch_env!(:pluteus, PluteusWeb.ForwardAuth)

    connect(ClientSocket, %{},
      connect_info: %{
        x_headers: [
          {Keyword.fetch!(config, :secret_header), Keyword.fetch!(config, :secret)},
          {Keyword.fetch!(config, :subject_header), subject}
        ]
      }
    )
  end

  defp remove(principal_id) do
    :ok = Sandbox.mode(Repo, :auto)
    id = Ecto.UUID.dump!(principal_id)

    res_ids =
      Repo.all(
        from w in "catalog_writes",
          where: w.principal_id == ^id and w.table_name == "res" and w.operation == "INSERT",
          select: type(fragment("(?->>'id')::uuid", w.row_key), Ecto.UUID)
      )

    for table <- ~w(resume_positions stars ratings playlists play_queues now_playing) do
      Repo.query!("DELETE FROM #{table} WHERE principal_id = $1", [id])
    end

    Repo.query!("DELETE FROM events WHERE principal_id = $1", [id])
    Repo.query!("DELETE FROM devices WHERE principal_id = $1", [id])

    # These tests commit for real, so they clean up after themselves rather than
    # rolling back. A work is five rows, two links, a category and an extent, every
    # one of them keyed on a res identifier about to be removed, so each goes before
    # its res does.
    {:ok, _} =
      Actor.as(principal_id, fn ->
        Repo.delete_all(from e in Extent, where: e.res_id in ^res_ids)
        Repo.delete_all(from c in Category, where: c.res_id in ^res_ids)

        Repo.delete_all(
          from e in Embodiment,
            where: e.expression_id in ^res_ids or e.manifestation_id in ^res_ids
        )

        Repo.delete_all(from m in Manifestation, where: m.id in ^res_ids)
        Repo.delete_all(from e in Expression, where: e.id in ^res_ids)
        Repo.delete_all(from w in Work, where: w.id in ^res_ids)

        Repo.delete_all(from n in Nomen, where: n.id in ^res_ids or n.res_id in ^res_ids)
        {:ok, Repo.delete_all(from r in Res, where: r.id in ^res_ids)}
      end)

    Repo.query!("DELETE FROM catalog_writes WHERE principal_id = $1", [id])
    Repo.query!("DELETE FROM principal_identities WHERE principal_id = $1", [id])
    Repo.query!("DELETE FROM principals WHERE id = $1", [id])

    :ok = Sandbox.mode(Repo, :manual)
  end
end
