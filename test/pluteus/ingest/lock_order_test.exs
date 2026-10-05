defmodule Pluteus.Ingest.LockOrderTest do
  @moduledoc """
  The order a placement takes the rows two placements contend for (spec-04 §6.1).

  Two placements running at once meet on a grouping key and on the artist keys their
  credits name. Taking them in one order is what makes them queue; taking them in two
  orders is a deadlock, and the pair that would deadlock are a placement creating a
  release and a placement joining one whose release has gone.

  Not async: the assertion is over every query the repo ran, and a test running beside it
  would put its own there too.
  """

  use Pluteus.DataCase, async: false

  import Pluteus.IngestFixtures

  alias Pluteus.Ingest
  alias Pluteus.Ingest.Credits
  alias Pluteus.Ingest.Place
  alias Pluteus.Ingest.ReleaseKey
  alias Pluteus.Ingest.Streams

  @t0 ~U[2026-09-18 12:00:00.000000Z]

  setup do
    %{inbox: inbox!()}
  end

  test "a release key is held before any artist key is taken", %{inbox: inbox} do
    acquisition = identified_track(inbox)

    # A key whose release has gone no longer groups anything and a new release takes it
    # over. That is the one path on which a placement creates a release while the key row
    # is already there, and so the one on which the key could be reached last.
    {:ok, key} = Place.release_key(acquisition, Streams.tags(acquisition.probe))
    now = DateTime.utc_now()
    {1, _} = Repo.insert_all(ReleaseKey, [%{key: key, inserted_at: now, updated_at: now}])

    queries = queries_during(fn -> Place.place_due(inbox) end)

    held = Enum.find_index(queries, &(&1 =~ "release_keys" and &1 =~ "FOR UPDATE"))
    artist = Enum.find_index(queries, &(&1 =~ "artist_keys"))

    assert held, "the release key was never locked"
    assert artist, "no artist key was taken, so this asserts nothing"
    assert held < artist, "the artist key was taken before the release key was held"
  end

  test "an artist key is held from the read rather than from the write" do
    # Two placements naming one artist queue on the key, so one artist is made for the
    # name. An insert that conflicts locks nothing, so the read is what holds it.
    queries = queries_during(fn -> Credits.artist_for("Bill Evans", nil) end)

    assert Enum.any?(queries, &(&1 =~ "artist_keys" and &1 =~ "FOR UPDATE"))
  end

  defp identified_track(inbox) do
    drop!(
      inbox,
      "KoB/01.flac",
      media!(:flac,
        tags: %{"album" => "Kind of Blue", "album_artist" => "Miles Davis", "track" => "1"}
      )
    )

    [id] = inbox |> acquire_settled!(@t0) |> acquired()

    Ingest.get_acquisition!(id)
  end

  defp queries_during(work) do
    handler = "lock-order-#{System.unique_integer([:positive])}"
    collector = self()

    :telemetry.attach(
      handler,
      [:pluteus, :repo, :query],
      fn _event, _measurements, metadata, pid -> send(pid, {handler, metadata.query}) end,
      collector
    )

    try do
      work.()
    after
      :telemetry.detach(handler)
    end

    drain(handler, [])
  end

  defp drain(handler, seen) do
    receive do
      {^handler, query} -> drain(handler, [query | seen])
    after
      0 -> Enum.reverse(seen)
    end
  end
end
