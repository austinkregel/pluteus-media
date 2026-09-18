defmodule Pluteus.LifecycleTest do
  @moduledoc """
  Recycle-bin behaviour spec-01 §14 requires that §15 does not enumerate: which
  way a deletion cascades, what travels with it, and who may empty it.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Lifecycle
  alias Pluteus.Principals

  setup do
    {:ok, ada} = Principals.create_principal(%{role: "member"})
    {:ok, bo} = Principals.create_principal(%{role: "member"})
    %{ada: ada, bo: bo}
  end

  describe "§14.3, recycling cascades downward and never upward" do
    test "a work takes its expression, manifestation, digital item and their names", %{ada: ada} do
      {:ok, %{work: work, expression: expression, manifestation: manifestation}} =
        Catalog.create_work("The Dig")

      {:ok, %{digital_item: digital_item}} =
        Catalog.create_digital_item(manifestation.id, "The Dig")

      {:ok, recycling} = Lifecycle.recycle(work.id, ada.id)
      held = Lifecycle.contents(recycling.id)

      for res <- [work, expression, manifestation, digital_item] do
        assert res.id in held
        assert Enum.all?(Catalog.nomens_for(res.id), &(&1.id in held))
      end
    end

    test "an expression leaves the work above it standing", %{ada: ada} do
      {:ok, %{work: work, expression: expression}} = Catalog.create_work("The Dig")

      {:ok, recycling} = Lifecycle.recycle(expression.id, ada.id)

      refute work.id in Lifecycle.contents(recycling.id)
      assert {:live, _res} = Lifecycle.state(work.id)
    end

    test "a container carrying another expression is not taken with the dub", %{ada: ada} do
      {:ok, %{work: work, manifestation: container}} = Catalog.create_work("The Dig")
      {:ok, %{expression: dub}} = Catalog.add_expression(work.id, "The Dig, Italian dub")
      {:ok, _} = Catalog.embody(dub.id, container.id)

      {:ok, recycling} = Lifecycle.recycle(dub.id, ada.id)

      refute container.id in Lifecycle.contents(recycling.id)
    end

    test "an item and a digital item go with their only manifestation", %{ada: ada} do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("Middlemarch")
      {:ok, %{item: item}} = Catalog.create_item(manifestation.id, "Ada's copy")

      {:ok, %{digital_item: digital_item}} =
        Catalog.create_digital_item(manifestation.id, "middlemarch.epub")

      {:ok, recycling} = Lifecycle.recycle(manifestation.id, ada.id)
      held = Lifecycle.contents(recycling.id)

      assert item.id in held
      assert digital_item.id in held
    end

    test "a subtitle cue goes with the expression it addresses", %{ada: ada} do
      {:ok, %{work: work, expression: expression}} = Catalog.create_work("The Dig")

      {:ok, %{address: cue}} =
        Catalog.create_address(expression.id, %{
          selector_type: :temporal,
          start_ms: 140_000,
          end_ms: 148_000
        })

      {:ok, recycling} = Lifecycle.recycle(work.id, ada.id)

      assert cue.id in Lifecycle.contents(recycling.id)
    end

    test "the container a dub shared is unlinked from it at purge", %{ada: ada} do
      {:ok, %{work: work, expression: original, manifestation: container}} =
        Catalog.create_work("The Dig")

      {:ok, %{expression: dub}} = Catalog.add_expression(work.id, "The Dig, Italian dub")
      {:ok, _} = Catalog.embody(dub.id, container.id)

      {:ok, recycling} = Lifecycle.recycle(dub.id, ada.id)
      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())

      assert {:live, _res} = Lifecycle.state(container.id)
      assert Enum.map(Catalog.expressions_in(container.id), & &1.id) == [original.id]
    end

    test "an album's tracks are not its children", %{ada: ada} do
      {:ok, %{expression: album}} = Catalog.create_work("Kind of Blue")
      {:ok, %{expression: track}} = Catalog.create_work("So What")
      {:ok, _} = Catalog.aggregate(album.id, track.id)

      {:ok, recycling} = Lifecycle.recycle(album.id, ada.id)
      refute track.id in Lifecycle.contents(recycling.id)

      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())

      assert {:live, _res} = Lifecycle.state(track.id)
      assert Catalog.arrangement_of(album.id, track.id) == nil
    end

    test "a personal name keeps its assigner when the assigner is purged", %{ada: ada} do
      %{grandmother: grandmother, child: child, childs_own: childs_own} =
        Pluteus.CatalogFixtures.kin_term!()

      {:ok, recycling} = Lifecycle.recycle(child.id, ada.id)
      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())

      name = Catalog.get_nomen(childs_own.id)

      assert name.res_id == grandmother.id
      assert name.assigner_id == child.id
      assert {:purged, _res, _tombstone} = Lifecycle.state(child.id)
    end

    test "something already in the bin stays with the deletion that put it there", %{ada: ada} do
      {:ok, %{work: work, expression: expression}} = Catalog.create_work("The Dig")

      {:ok, first} = Lifecycle.recycle(expression.id, ada.id)
      {:ok, second} = Lifecycle.recycle(work.id, ada.id)

      refute expression.id in Lifecycle.contents(second.id)

      {:ok, _} = Lifecycle.restore(second.id)

      assert {:recycled, _res, %{id: id}} = Lifecycle.state(expression.id)
      assert id == first.id
    end

    test "a res already in the bin cannot be recycled twice", %{ada: ada} do
      {:ok, %{work: work}} = Catalog.create_work("The Dig")
      {:ok, _} = Lifecycle.recycle(work.id, ada.id)

      assert {:error, :already_recycled} = Lifecycle.recycle(work.id, ada.id)
    end
  end

  describe "§14.3, deleting an album with its tracks" do
    setup do
      {:ok, %{work: album_work, expression: album}} = Catalog.create_work("Kind of Blue")

      {:ok, %{work: song, expression: track, manifestation: take}} =
        Catalog.create_work("So What")

      {:ok, _} = Catalog.aggregate(album.id, track.id)

      %{album_work: album_work, album: album, song: song, track: track, take: take}
    end

    test "takes each track, its recording and the song", %{ada: ada} = context do
      {:ok, recycling} =
        Lifecycle.recycle(context.album_work.id, ada.id, with_aggregated: true)

      held = Lifecycle.contents(recycling.id)

      for res <- [context.album, context.track, context.take, context.song] do
        assert res.id in held
      end
    end

    test "leaves a track that a compilation also carries", %{ada: ada} = context do
      {:ok, %{expression: compilation}} = Catalog.create_work("Jazz Essentials")
      {:ok, _} = Catalog.aggregate(compilation.id, context.track.id)

      {:ok, recycling} =
        Lifecycle.recycle(context.album_work.id, ada.id, with_aggregated: true)

      refute context.track.id in Lifecycle.contents(recycling.id)

      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())

      assert {:live, _res} = Lifecycle.state(context.track.id)
      assert Catalog.arrangement_of(compilation.id, context.track.id) == nil
      assert Catalog.arrange(compilation.id, context.track.id, 1) == 1
      assert Catalog.arrangement_of(compilation.id, context.track.id) == 1
    end

    test "keeps the song when a live recording of it is elsewhere", %{ada: ada} = context do
      {:ok, %{expression: live}} = Catalog.add_expression(context.song.id, "So What, live 1960")

      {:ok, recycling} =
        Lifecycle.recycle(context.album_work.id, ada.id, with_aggregated: true)

      held = Lifecycle.contents(recycling.id)

      assert context.track.id in held
      refute context.song.id in held
      refute live.id in held
    end

    test "a box set takes its albums and their tracks", %{ada: ada} = context do
      {:ok, %{work: box}} = Catalog.create_work("The Complete Columbia Recordings")
      [box_expression] = Catalog.expressions_of(box.id)
      {:ok, _} = Catalog.aggregate(box_expression.id, context.album.id)

      {:ok, recycling} = Lifecycle.recycle(box.id, ada.id, with_aggregated: true)
      held = Lifecycle.contents(recycling.id)

      assert context.album.id in held
      assert context.track.id in held
      assert context.song.id in held
    end

    test "and one restoration brings all of it back", %{ada: ada} = context do
      {:ok, recycling} =
        Lifecycle.recycle(context.album_work.id, ada.id, with_aggregated: true)

      {:ok, _} = Lifecycle.restore(recycling.id)

      for res <- [context.album, context.track, context.song] do
        assert {:live, _res} = Lifecycle.state(res.id)
      end
    end
  end

  describe "§14.1, emptying the bin" do
    test "a principal may empty its own deletion", %{ada: ada} do
      {:ok, %{work: work}} = Catalog.create_work("The Dig")
      {:ok, recycling} = Lifecycle.recycle(work.id, ada.id)

      assert {:ok, %{purged: purged}} = Lifecycle.empty(recycling.id, ada.id)
      assert work.id in purged
    end

    test "and may not empty another principal's", %{ada: ada, bo: bo} do
      {:ok, %{work: work}} = Catalog.create_work("The Dig")
      {:ok, recycling} = Lifecycle.recycle(work.id, ada.id)

      assert {:error, :not_this_principals_deletion} = Lifecycle.empty(recycling.id, bo.id)
      assert {:recycled, _res, _recycling} = Lifecycle.state(work.id)
    end

    test "the window closes after thirty days and not before", %{ada: ada} do
      {:ok, %{work: kept}} = Catalog.create_work("The Dig")
      {:ok, %{work: gone}} = Catalog.create_work("Middlemarch")

      now = DateTime.utc_now()
      {:ok, _} = Lifecycle.recycle(kept.id, ada.id, now: DateTime.add(now, -29 * 86_400, :second))
      {:ok, _} = Lifecycle.recycle(gone.id, ada.id, now: DateTime.add(now, -31 * 86_400, :second))

      Lifecycle.purge_expired(now)

      assert {:recycled, _res, _recycling} = Lifecycle.state(kept.id)
      assert {:purged, _res, _tombstone} = Lifecycle.state(gone.id)
    end

    test "a purged res cannot be recycled", %{ada: ada} do
      {:ok, %{work: work}} = Catalog.create_work("The Dig")
      {:ok, recycling} = Lifecycle.recycle(work.id, ada.id)
      {:ok, _} = Lifecycle.empty(recycling.id, ada.id)

      assert {:error, :purged} = Lifecycle.recycle(work.id, ada.id)
    end
  end
end
