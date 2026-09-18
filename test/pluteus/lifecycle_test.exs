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
      {:ok, _} = Lifecycle.recycle(kept.id, ada.id, DateTime.add(now, -29 * 86_400, :second))
      {:ok, _} = Lifecycle.recycle(gone.id, ada.id, DateTime.add(now, -31 * 86_400, :second))

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
