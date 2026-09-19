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

    test "recycling, restoring and purging each name the res", %{actor: principal} do
      {:ok, %{work: work}} = Catalog.create_work("Kind of Blue")

      {:ok, recycling} = Lifecycle.recycle(work.id, principal.id)
      assert [{"INSERT", [id]}] = writes("recycled_res", work.id)
      assert id == work.id

      {:ok, _} = Lifecycle.restore(recycling.id)
      assert [{"INSERT", _}, {"DELETE", [^id]}] = writes("recycled_res", work.id)

      {:ok, recycling} = Lifecycle.recycle(work.id, principal.id)
      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())
      assert [{"INSERT", [^id]}] = writes("tombstones", work.id)
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
