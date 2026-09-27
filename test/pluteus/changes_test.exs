defmodule Pluteus.ChangesTest do
  @moduledoc """
  What the change feed records of each write (spec-07 §5.1): the identifiers
  of every res in the row it wrote, lifecycle changes included.
  """

  use Pluteus.DataCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Lifecycle
  alias Pluteus.Lifecycle.Tombstone
  alias Pluteus.Repo

  @subtype_parents ~w(res)

  describe "a write names every res in its row" do
    test "a name names itself, the res it names, and its assigner" do
      {:ok, %{res: assigner}} = Catalog.create_named_res(:person, "Ada")
      {:ok, %{work: work}} = Catalog.create_work("Untitled")

      {:ok, nomen} =
        Catalog.create_nomen(%{
          res_id: work.id,
          nomen_string: "Titled",
          assigner_id: assigner.id,
          provenance: :local
        })

      assert [{"INSERT", res}] = writes("nomens", nomen.id)
      assert Enum.sort(res) == Enum.sort([nomen.id, work.id, assigner.id])
    end

    test "an update names the res of the row before it as well as after" do
      {:ok, %{res: before}} = Catalog.create_named_res(:person, "Ada")
      {:ok, %{res: later}} = Catalog.create_named_res(:person, "Grace")
      {:ok, %{work: work}} = Catalog.create_work("Untitled")

      {:ok, nomen} =
        Catalog.create_nomen(%{
          res_id: work.id,
          nomen_string: "Titled",
          assigner_id: before.id,
          provenance: :local
        })

      {1, _} =
        Repo.update_all(from(n in Nomen, where: n.id == ^nomen.id), set: [assigner_id: later.id])

      assert [{"INSERT", _}, {"UPDATE", res}] = writes("nomens", nomen.id)
      assert before.id in res and later.id in res
    end

    test "recycling and restoring each name the res", %{actor: principal} do
      {:ok, %{work: work}} = Catalog.create_work("Kind of Blue")

      {:ok, recycling} = Lifecycle.recycle(work.id, principal.id)
      assert [{"INSERT", [id]}] = writes("recycled_res", work.id)
      assert id == work.id

      {:ok, _} = Lifecycle.restore(recycling.id)
      assert [{"INSERT", _}, {"DELETE", [^id]}] = writes("recycled_res", work.id)
    end
  end

  describe "spec-01 43. Purging a res emits no change notification" do
    test "the recycling is the last thing the feed says about it", %{actor: principal} do
      {:ok, %{work: work}} = Catalog.create_work("Kind of Blue")
      {:ok, recycling} = Lifecycle.recycle(work.id, principal.id)

      before = writes("recycled_res", work.id)
      assert [{"INSERT", [work.id]}] == before

      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())

      # The purge happened, and said nothing. Not the tombstone it wrote, not the
      # rows it deleted from the structural tables, and not the recycled_res rows
      # the recycling's own deletion cascaded away.
      assert {:purged, _, _} = Lifecycle.state(work.id)
      assert writes("tombstones", work.id) == []
      assert writes("works", work.id) == [{"INSERT", [work.id]}]
      assert writes("recycled_res", work.id) == before
    end

    test "spec-06 15. The purge still records the acting principal", %{actor: principal} do
      {:ok, %{work: work}} = Catalog.create_work("Kind of Blue")
      {:ok, recycling} = Lifecycle.recycle(work.id, principal.id)
      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())

      # §6.2 requires every catalog write to record the acting principal. With no
      # feed row to carry it, the tombstone does.
      assert Repo.get!(Tombstone, work.id).purged_by == principal.id
    end

    test "a write outside the purge is still recorded, and one with no actor still raises",
         %{actor: principal} do
      {:ok, %{work: work}} = Catalog.create_work("Kind of Blue")
      {:ok, recycling} = Lifecycle.recycle(work.id, principal.id)
      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())

      # The setting is cleared before the purge's transaction closes, so the
      # transaction enclosing it is not left silenced.
      {:ok, %{work: after_purge}} = Catalog.create_work("Sketches of Spain")
      assert [{"INSERT", [_]}] = writes("works", after_purge.id)

      :ok = Pluteus.Actor.set("")

      error = assert_raise Postgrex.Error, fn -> Catalog.create_work("Anonymous") end
      assert error.postgres.message =~ "no acting principal"
    end
  end

  test "every recorded table declares exactly the columns that hold a res" do
    declared =
      Map.new(
        Repo.query!("""
        SELECT c.relname, pg_get_triggerdef(t.oid)
        FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
        WHERE t.tgname = 'record_catalog_write'
        """).rows,
        fn [table, definition] ->
          [_, res] = Regex.run(~r/record_catalog_write\('\{[^}]*\}', '\{([^}]*)\}'\)/, definition)
          {table, res |> String.split(",") |> Enum.sort()}
        end
      )

    subtypes =
      Repo.query!(
        """
        SELECT cl.relname FROM pg_constraint con
        JOIN pg_class cl ON cl.oid = con.conrelid
        JOIN pg_class rc ON rc.oid = con.confrelid
        JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = con.conkey[1]
        WHERE con.contype = 'f' AND a.attname = 'id' AND rc.relname = ANY($1)
        """,
        [@subtype_parents]
      ).rows
      |> List.flatten()

    holding_res =
      Repo.query!(
        """
        SELECT cl.relname, a.attname FROM pg_constraint con
        JOIN pg_class cl ON cl.oid = con.conrelid
        JOIN pg_class rc ON rc.oid = con.confrelid
        JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = con.conkey[1]
        WHERE con.contype = 'f' AND rc.relname = ANY($1) AND cl.relname = ANY($2)
        """,
        [@subtype_parents ++ subtypes, Map.keys(declared)]
      ).rows
      |> Enum.group_by(&hd/1, &List.last/1)
      |> Map.new(fn {table, columns} -> {table, Enum.sort(columns)} end)
      |> Map.put("res", ["id"])

    assert declared == holding_res
  end

  defp writes(table, res_id) do
    Repo.all(
      from w in "catalog_writes",
        where: w.table_name == ^table and ^Ecto.UUID.dump!(res_id) in w.res_ids,
        order_by: w.id,
        select: {w.operation, type(w.res_ids, {:array, Ecto.UUID})}
    )
  end
end
