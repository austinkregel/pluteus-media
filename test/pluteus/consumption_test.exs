defmodule Pluteus.ConsumptionTest do
  @moduledoc """
  Each principal's own consumption data: spec-07 §6.5, §6.6 and criteria 10,
  18 and 19, at the layer the surfaces are built on.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Consumption
  alias Pluteus.Events
  alias Pluteus.Lifecycle
  alias Pluteus.PrincipalFixtures
  alias Pluteus.Principals

  setup %{actor: ada} do
    {:ok, bo} = Principals.create_principal(%{role: "member"})

    songs =
      for title <- ~w(Summertime Freddie Blue) do
        {:ok, %{manifestation: manifestation}} = Catalog.create_work(title)
        manifestation.id
      end

    devices =
      for {principal, label} <- [{ada, "phone"}, {ada, "desk"}, {bo, "tablet"}], into: %{} do
        {label, PrincipalFixtures.a_device(principal.id, label).id}
      end

    %{ada: ada, bo: bo, songs: songs, devices: devices}
  end

  test "every function takes the principal whose data it reads or writes first" do
    assert Enum.sort(Consumption.__info__(:functions)) == [
             bookmark: 5,
             bookmarks: 1,
             create_playlist: 3,
             delete_bookmark: 2,
             delete_playlist: 2,
             now_playing: 1,
             play_queue: 1,
             played: 3,
             played: 4,
             playing: 3,
             playing: 4,
             playlist: 2,
             playlists: 1,
             rate: 3,
             ratings: 2,
             reached: 3,
             save_play_queue: 5,
             star: 2,
             star: 3,
             starred: 1,
             starred_at: 2,
             unstar: 2,
             update_playlist: 3
           ]
  end

  describe "stars" do
    test "are the principal's own, and a second star keeps the first time", %{
      ada: ada,
      bo: bo,
      songs: [song | _]
    } do
      first = ~U[2026-09-01 10:00:00.000000Z]
      {:ok, _} = Consumption.star(ada.id, song, first)
      {:ok, _} = Consumption.star(ada.id, song, ~U[2026-09-02 10:00:00.000000Z])

      assert [%{res_id: ^song, starred_at: ^first}] = Consumption.starred(ada.id)
      assert Consumption.starred_at(ada.id, [song]) == %{song => first}
      assert Consumption.starred(bo.id) == []
      assert Consumption.starred_at(bo.id, [song]) == %{}

      :ok = Consumption.unstar(bo.id, song)
      assert [_] = Consumption.starred(ada.id)

      :ok = Consumption.unstar(ada.id, song)
      assert Consumption.starred(ada.id) == []
    end

    test "are listed most recent first", %{ada: ada, songs: [a, b | _]} do
      {:ok, _} = Consumption.star(ada.id, a, ~U[2026-09-01 10:00:00.000000Z])
      {:ok, _} = Consumption.star(ada.id, b, ~U[2026-09-02 10:00:00.000000Z])

      assert Enum.map(Consumption.starred(ada.id), & &1.res_id) == [b, a]
    end

    test "outlive the purge of what they name", %{ada: ada, songs: [song | _]} do
      {:ok, _} = Consumption.star(ada.id, song)
      {:ok, recycling} = Lifecycle.recycle(song, ada.id)
      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())

      assert [%{res_id: ^song}] = Consumption.starred(ada.id)
    end
  end

  describe "ratings" do
    test "run one to five, zero clears, and each principal has its own", %{
      ada: ada,
      bo: bo,
      songs: [song | _]
    } do
      {:ok, _} = Consumption.rate(ada.id, song, 4)
      {:ok, _} = Consumption.rate(ada.id, song, 5)
      {:ok, _} = Consumption.rate(bo.id, song, 1)

      assert Consumption.ratings(ada.id, [song]) == %{song => 5}
      assert Consumption.ratings(bo.id, [song]) == %{song => 1}

      assert {:error, changeset} = Consumption.rate(ada.id, song, 6)
      assert %{rating: [_]} = errors_on(changeset)

      {:ok, nil} = Consumption.rate(ada.id, song, 0)
      assert Consumption.ratings(ada.id, [song]) == %{}
      assert Consumption.ratings(bo.id, [song]) == %{song => 1}
    end
  end

  describe "19. Another principal's playlist is not found, read, changed or deleted" do
    test "each of these is refused as absent", %{ada: ada, bo: bo, songs: songs} do
      {:ok, playlist} = Consumption.create_playlist(ada.id, "Evening", songs)

      assert Consumption.playlist(bo.id, playlist.id) == nil
      assert Consumption.playlists(bo.id) == []

      assert {:error, :not_found} =
               Consumption.update_playlist(bo.id, playlist.id, %{name: "Taken"})

      assert {:error, :not_found} = Consumption.delete_playlist(bo.id, playlist.id)
      assert Consumption.playlist(ada.id, playlist.id).name == "Evening"
    end
  end

  describe "playlists" do
    test "keep their songs in order, repeats included", %{ada: ada, songs: [a, b, c]} do
      {:ok, playlist} = Consumption.create_playlist(ada.id, "Evening", [a, b, a, c])

      assert entries(playlist) == [a, b, a, c]
      assert [%{id: id}] = Consumption.playlists(ada.id)
      assert id == playlist.id
    end

    test "are edited by removing positions and then appending", %{ada: ada, songs: [a, b, c]} do
      {:ok, playlist} = Consumption.create_playlist(ada.id, "Evening", [a, b, c])

      {:ok, edited} =
        Consumption.update_playlist(ada.id, playlist.id, %{
          name: "Night",
          comment: "late",
          remove: [0, 2],
          append: [a]
        })

      assert entries(edited) == [b, a]
      assert {edited.name, edited.comment} == {"Night", "late"}
      assert DateTime.compare(edited.updated_at, playlist.updated_at) == :gt
    end

    test "are replaced whole by songs", %{ada: ada, songs: [a, b, c]} do
      {:ok, playlist} = Consumption.create_playlist(ada.id, "Evening", [a, b])
      {:ok, replaced} = Consumption.update_playlist(ada.id, playlist.id, %{songs: [c, a]})

      assert entries(replaced) == [c, a]
      assert replaced.name == "Evening"
    end

    test "are deleted by their principal", %{ada: ada, songs: songs} do
      {:ok, playlist} = Consumption.create_playlist(ada.id, "Evening", songs)

      assert :ok = Consumption.delete_playlist(ada.id, playlist.id)
      assert Consumption.playlist(ada.id, playlist.id) == nil
    end
  end

  describe "the play queue" do
    test "is saved with its current entry and replaced by the next save", %{
      ada: ada,
      devices: devices,
      bo: bo,
      songs: [a, b, c]
    } do
      {:ok, queue} =
        Consumption.save_play_queue(ada.id, queued([a, b, a]), 2, 90_000, devices["phone"])

      assert entries(queue) == [a, b, a]

      assert {queue.current_index, queue.position_ms, queue.changed_by_device_id} ==
               {2, 90_000, devices["phone"]}

      {:ok, queue} = Consumption.save_play_queue(ada.id, queued([c]), 0, 0, devices["desk"])
      assert entries(queue) == [c]
      assert queue.changed_by_device_id == devices["desk"]

      assert Consumption.play_queue(bo.id) == nil
    end

    test "refuses a current entry outside it, and an empty save clears it", %{
      ada: ada,
      devices: devices,
      bo: bo,
      songs: [a, b | _]
    } do
      {:ok, _} = Consumption.save_play_queue(bo.id, queued([b]), 0, 0, devices["tablet"])

      assert {:error, :current_outside_queue} =
               Consumption.save_play_queue(ada.id, queued([a, b]), 2, 0, devices["phone"])

      {:ok, _} = Consumption.save_play_queue(ada.id, queued([a, b]), nil, 0, devices["phone"])
      assert Consumption.play_queue(ada.id).current_index == nil

      {:ok, nil} = Consumption.save_play_queue(ada.id, [], nil, 0, devices["phone"])
      assert Consumption.play_queue(ada.id) == nil
      assert entries(Consumption.play_queue(bo.id)) == [b]
    end

    test "§12.3. An entry records the grouping it was queued from", %{
      ada: ada,
      devices: devices,
      songs: [a, b | _]
    } do
      # So that "clear the rest of this release" is answerable without guessing, which
      # the res alone cannot answer: the same song queued from a release and queued on
      # its own are different entries.
      {:ok, %{work: release}} = Catalog.create_work("Kind of Blue")

      {:ok, queue} =
        Consumption.save_play_queue(
          ada.id,
          [%{res_id: a, queued_from: nil}, %{res_id: b, queued_from: release.id}],
          0,
          0,
          devices["phone"]
        )

      assert Enum.map(queue.entries, &{&1.res_id, &1.queued_from}) ==
               [{a, nil}, {b, release.id}]
    end
  end

  describe "devices" do
    test "a principal's data can name only its own devices", %{
      ada: ada,
      devices: devices,
      songs: [a | _]
    } do
      assert_raise Postgrex.Error, ~r/now_playing_device_id_fkey/, fn ->
        Consumption.playing(ada.id, devices["tablet"], a)
      end
    end
  end

  describe "bookmarks" do
    test "are the principal's resume positions, with a comment", %{
      ada: ada,
      bo: bo,
      devices: devices,
      songs: [song | _]
    } do
      phone = devices["phone"]

      {:ok, _} = Consumption.bookmark(ada.id, song, phone, 61_000, "the solo")
      {:ok, _} = Consumption.bookmark(ada.id, song, phone, 62_000, "after the solo")

      assert [%{position: 62_000, comment: "after the solo"}] = Consumption.bookmarks(ada.id)
      assert Events.resume_position(ada.id, song).position == 62_000
      assert Consumption.bookmarks(bo.id) == []

      assert {:error, :not_found} = Consumption.delete_bookmark(bo.id, song)
      assert :ok = Consumption.delete_bookmark(ada.id, song)
      assert Consumption.bookmarks(ada.id) == []
    end

    test "a bookmark is kept wherever a session's report would be discarded", %{
      ada: ada,
      devices: devices,
      songs: [song | _]
    } do
      # [spec-10] §13.2's floor is what a reporting session is weighed by. A
      # bookmark is a person's explicit act, so one near the start is kept where a
      # session's report of the same position would be discarded as barely begun.
      {:ok, bookmark} = Consumption.bookmark(ada.id, song, devices["phone"], 1_000, "the intro")

      assert bookmark.position == 1_000
      refute bookmark.playing
    end

    test "a bookmark is one per device, as every position is", %{
      ada: ada,
      devices: devices,
      songs: [song | _]
    } do
      {:ok, _} = Consumption.bookmark(ada.id, song, devices["phone"], 61_000, "on the phone")
      {:ok, _} = Consumption.bookmark(ada.id, song, devices["desk"], 4_000, "at the desk")

      # Two rows, and the continue surface shows one entry for the res.
      assert [_, _] = Events.positions_for(ada.id, song)
      assert [one] = Consumption.bookmarks(ada.id)
      assert one.res_id == song
    end
  end

  describe "now playing and plays" do
    test "playing is per device and no event; a play is an event that ends it", %{
      ada: ada,
      devices: devices,
      bo: bo,
      songs: [a, b | _]
    } do
      :ok = Consumption.playing(ada.id, devices["phone"], a)
      :ok = Consumption.playing(ada.id, devices["desk"], b)
      :ok = Consumption.playing(ada.id, devices["phone"], b)

      assert ada.id
             |> Consumption.now_playing()
             |> Enum.map(&{&1.device_id, &1.res_id})
             |> Enum.sort() ==
               Enum.sort([{devices["desk"], b}, {devices["phone"], b}])

      assert Events.for_principal(ada.id) == []
      assert Consumption.now_playing(bo.id) == []

      {:ok, event} = Consumption.played(ada.id, devices["phone"], b)

      assert {event.principal_id, event.res_id, event.type} == {ada.id, b, "played"}
      assert [%{device_id: desk}] = Consumption.now_playing(ada.id)
      assert desk == devices["desk"]
      assert event.device_id == devices["phone"]
      assert Events.play_count(ada.id, b, "played") == 1
      assert Events.play_count(bo.id, b, "played") == 0
    end
  end

  defp entries(%{entries: entries}), do: Enum.map(entries, & &1.res_id)

  # A queue of entries queued from nothing, which is what a list of res on its own is.
  defp queued(res_ids), do: for(res_id <- res_ids, do: %{res_id: res_id, queued_from: nil})
end
