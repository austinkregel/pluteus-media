defmodule Pluteus.Lifecycle do
  @moduledoc """
  Deletion, restoration and purge (spec-01 §14).

  Deleting something recycles it. Recycling is a catalog state and nothing
  further: no stored byte is moved, rewritten or removed while an entity is in
  the bin, which is what makes restoration exact. It cascades downward through
  the structural chain as one grouped operation, never upward, and a res's
  nomens travel with it.

  Purge is permanent. The entity's rows and its bytes in primary storage go;
  the res row stays as the tombstone, with a record of when it was purged.
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Pluteus.Assets
  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.Aggregation
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Extent
  alias Pluteus.Catalog.Item
  alias Pluteus.Catalog.Manifestation
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Res
  alias Pluteus.Catalog.Verification
  alias Pluteus.Catalog.Work
  alias Pluteus.Catalog.WorkPart
  alias Pluteus.Lifecycle.RecycledRes
  alias Pluteus.Lifecycle.Recycling
  alias Pluteus.Lifecycle.Tombstone
  alias Pluteus.Repo
  alias Pluteus.Storage

  @window_days 30

  @doc """
  Where a res stands.

  `:absent` means no res ever carried the identifier. A purged one is never
  absent: its tombstone answers for it.
  """
  @spec state(Ecto.UUID.t()) ::
          {:live, Res.t()}
          | {:recycled, Res.t(), Recycling.t()}
          | {:purged, Res.t(), Tombstone.t()}
          | :absent
  def state(res_id) do
    case Repo.get(Res, res_id) do
      nil -> :absent
      %Res{} = res -> state_of(res)
    end
  end

  @doc """
  Places a res in the recycle bin, with everything below it.

  The window is #{@window_days} days (§14.1). Anything below the res that is
  already in the bin stays with the deletion that put it there, so restoring
  this one does not undo that one.

  Options:

    * `:with_aggregated` — also take what an aggregate selects, so an album goes
      with its tracks (§14.3). A track another live aggregate selects stays.
    * `:now` — the moment of deletion, from which the window runs.
  """
  @spec recycle(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
          {:ok, Recycling.t()} | {:error, atom()}
  def recycle(res_id, principal_id, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    case state(res_id) do
      {:live, res} ->
        insert_recycling(res, principal_id, now, Keyword.get(opts, :with_aggregated, false))

      {:recycled, _res, _recycling} ->
        {:error, :already_recycled}

      {:purged, _res, _tombstone} ->
        {:error, :purged}

      :absent ->
        {:error, :no_such_res}
    end
  end

  @doc """
  Every res one recycling holds.
  """
  @spec contents(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def contents(recycling_id) do
    Repo.all(from r in RecycledRes, where: r.recycling_id == ^recycling_id, select: r.res_id)
  end

  @doc """
  Takes everything one recycling holds back out of the bin.

  Nothing moved when it went in, so nothing moves now: every res is reachable
  at the identifier it always had.
  """
  @spec restore(Ecto.UUID.t()) :: {:ok, [Ecto.UUID.t()]} | {:error, atom()}
  def restore(recycling_id) do
    case Repo.get(Recycling, recycling_id) do
      nil ->
        {:error, :no_such_recycling}

      %Recycling{} = recycling ->
        restored = contents(recycling.id)
        {:ok, _} = Repo.delete(recycling)
        {:ok, restored}
    end
  end

  @doc """
  Purges one principal's own deletion ahead of its window.

  §14.1 lets a principal empty its own deletions. Emptying another's destroys
  the window that makes the bin a safety net, and is an administrative
  operation spec-06 §6 governs; it is refused here.
  """
  @spec empty(Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) ::
          {:ok, map()} | {:error, atom()}
  def empty(recycling_id, principal_id, now \\ DateTime.utc_now()) do
    case Repo.get(Recycling, recycling_id) do
      nil -> {:error, :no_such_recycling}
      %Recycling{recycled_by: ^principal_id} = recycling -> purge(recycling, now)
      %Recycling{} -> {:error, :not_this_principals_deletion}
    end
  end

  @doc """
  Purges every recycling whose window has closed.
  """
  @spec purge_expired(DateTime.t()) :: [map()]
  def purge_expired(now \\ DateTime.utc_now()) do
    from(r in Recycling, where: r.purge_after <= ^now)
    |> Repo.all()
    |> Enum.map(fn recycling ->
      {:ok, result} = purge(recycling, now)
      result
    end)
  end

  @doc """
  Permanently removes what one recycling holds.

  The catalog is written first and the bytes removed after it commits. The
  other order could remove bytes for an entity whose purge then rolled back,
  which would turn a failed purge into a loss. Any byte sequence that could not
  be removed is returned rather than raised, so every failure in the set is
  reported and not only the first.
  """
  @spec purge(Recycling.t(), DateTime.t()) :: {:ok, map()}
  def purge(%Recycling{} = recycling, now) do
    res_ids = contents(recycling.id)
    locations = Repo.all(from a in Asset, where: a.id in ^res_ids, select: a.location)

    {:ok, _changes} =
      Multi.new()
      |> delete_structure(res_ids)
      |> Multi.run(:tombstones, fn repo, _changes -> entomb(repo, res_ids, now) end)
      |> Multi.delete(:recycling, recycling)
      |> Repo.transaction()

    bytes_not_removed =
      for location <- locations,
          {:error, reason} <- [Storage.delete(location)],
          do: {location, reason}

    {:ok, %{purged: res_ids, bytes_not_removed: bytes_not_removed}}
  end

  defp state_of(%Res{id: id} = res) do
    case Repo.get(Tombstone, id) do
      %Tombstone{} = tombstone ->
        {:purged, res, tombstone}

      nil ->
        case Repo.get(RecycledRes, id) do
          nil -> {:live, res}
          %RecycledRes{} = held -> {:recycled, res, Repo.get!(Recycling, held.recycling_id)}
        end
    end
  end

  defp insert_recycling(%Res{} = res, principal_id, now, with_aggregated) do
    unavailable = unavailable()
    held = closure(res)
    held = if with_aggregated, do: with_aggregated(held, unavailable), else: held
    held = Enum.reject(held, &(&1 in unavailable))

    Multi.new()
    |> Multi.insert(
      :recycling,
      Recycling.changeset(%Recycling{}, %{
        root_id: res.id,
        recycled_by: principal_id,
        recycled_at: now,
        purge_after: DateTime.add(now, @window_days * 24 * 60 * 60, :second)
      })
    )
    |> Multi.run(:held, fn repo, %{recycling: recycling} ->
      rows =
        Enum.map(held, fn res_id ->
          %{res_id: res_id, recycling_id: recycling.id, inserted_at: now, updated_at: now}
        end)

      {count, _} = repo.insert_all(RecycledRes, rows)
      {:ok, count}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{recycling: recycling}} -> {:ok, recycling}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp unavailable do
    Repo.all(from(r in RecycledRes, select: r.res_id)) ++
      Repo.all(from(t in Tombstone, select: t.res_id))
  end

  # §14.3: a res goes with a parent that is its only one. Addresses are
  # gathered after the structure because a cue's parent may be anything the
  # structural pass took, and nomens last because every res taken carries its
  # own.
  defp closure(%Res{id: id, kind: kind}) do
    structural = [id | below(kind, [id])]
    assets = Repo.all(from a in Asset, where: a.id in ^structural, select: a.id)
    coupled = Enum.flat_map(assets, &Assets.coupled_to/1)
    held = Enum.uniq(structural ++ coupled)

    addressed = Repo.all(from a in Address, where: a.target_id in ^held, select: a.id)
    held = Enum.uniq(held ++ addressed)

    Enum.uniq(held ++ Repo.all(from n in Nomen, where: n.res_id in ^held, select: n.id))
  end

  # Repeats until an aggregate selects nothing further, so a box set takes its
  # albums and then their tracks. An expression another live aggregate selects
  # is shared and stays. A work goes only when every expression it has is gone
  # or going, which is the single place recycling reaches upward.
  defp with_aggregated(held, unavailable) do
    gone = MapSet.new(held ++ unavailable)

    candidates =
      from(a in Aggregation,
        where: a.aggregating_expression_id in ^held,
        select: a.aggregated_expression_id,
        distinct: true
      )
      |> Repo.all()
      |> Enum.reject(&(&1 in gone))

    selections =
      Repo.all(
        from a in Aggregation,
          where: a.aggregated_expression_id in ^candidates,
          select: {a.aggregated_expression_id, a.aggregating_expression_id}
      )

    taken =
      Enum.filter(candidates, fn candidate ->
        selections
        |> Enum.filter(fn {selected, _by} -> selected == candidate end)
        |> Enum.all?(fn {_selected, by} -> by in gone end)
      end)

    case taken do
      [] ->
        held

      _ ->
        reach = Enum.uniq(taken ++ works_left_empty(taken, gone))
        additions = Enum.flat_map(reach, &closure(Repo.get!(Res, &1)))
        with_aggregated(Enum.uniq(held ++ additions), unavailable)
    end
  end

  defp works_left_empty(expression_ids, gone) do
    going = MapSet.union(gone, MapSet.new(expression_ids))

    from(e in Expression, where: e.id in ^expression_ids, select: e.work_id, distinct: true)
    |> Repo.all()
    |> Enum.filter(fn work_id ->
      from(e in Expression, where: e.work_id == ^work_id, select: e.id)
      |> Repo.all()
      |> Enum.all?(&(&1 in going))
    end)
  end

  defp below(:work, work_ids) do
    expressions = Repo.all(from e in Expression, where: e.work_id in ^work_ids, select: e.id)
    expressions ++ below(:expression, expressions)
  end

  defp below(:expression, expression_ids) do
    manifestations = wholly_embodied_by(expression_ids)
    manifestations ++ below(:manifestation, manifestations)
  end

  defp below(:manifestation, manifestation_ids) do
    items =
      Repo.all(from i in Item, where: i.manifestation_id in ^manifestation_ids, select: i.id)

    digital_items =
      Repo.all(
        from d in DigitalItem, where: d.manifestation_id in ^manifestation_ids, select: d.id
      )

    items ++ digital_items ++ below(:digital_item, digital_items)
  end

  defp below(:digital_item, digital_item_ids) do
    Repo.all(from a in Asset, where: a.digital_item_id in ^digital_item_ids, select: a.id)
  end

  defp below(_kind, _ids), do: []

  # A manifestation embodying several expressions goes only when every one of
  # them does. Deleting the Italian dub of a film must not take the container
  # that also carries the original audio; the container is unlinked from the dub
  # at purge instead.
  defp wholly_embodied_by(expression_ids) do
    going = MapSet.new(expression_ids)

    candidates =
      Repo.all(
        from e in Embodiment,
          where: e.expression_id in ^expression_ids,
          select: e.manifestation_id,
          distinct: true
      )

    embodiments =
      Repo.all(
        from e in Embodiment,
          where: e.manifestation_id in ^candidates,
          select: {e.manifestation_id, e.expression_id}
      )

    Enum.filter(candidates, fn manifestation_id ->
      embodiments
      |> Enum.filter(fn {m, _e} -> m == manifestation_id end)
      |> Enum.all?(fn {_m, expression_id} -> expression_id in going end)
    end)
  end

  # Children before parents, so that no foreign key is left pointing at a row
  # already gone. The res rows themselves are kept as tombstones.
  defp delete_structure(multi, ids) do
    [
      verifications: from(v in Verification, where: v.asset_id in ^ids),
      assets: from(a in Asset, where: a.id in ^ids),
      digital_items: from(d in DigitalItem, where: d.id in ^ids),
      items: from(i in Item, where: i.id in ^ids),
      embodiments:
        from(e in Embodiment, where: e.expression_id in ^ids or e.manifestation_id in ^ids),
      aggregations:
        from(a in Aggregation,
          where: a.aggregating_expression_id in ^ids or a.aggregated_expression_id in ^ids
        ),
      work_parts: from(w in WorkPart, where: w.whole_id in ^ids or w.part_id in ^ids),
      manifestations: from(m in Manifestation, where: m.id in ^ids),
      expressions: from(e in Expression, where: e.id in ^ids),
      works: from(w in Work, where: w.id in ^ids),
      extents: from(x in Extent, where: x.res_id in ^ids),
      addresses: from(a in Address, where: a.id in ^ids),
      nomens: from(n in Nomen, where: n.id in ^ids)
    ]
    |> Enum.reduce(multi, fn {name, query}, acc -> Multi.delete_all(acc, name, query) end)
  end

  defp entomb(repo, ids, now) do
    rows =
      Repo.all(from r in Res, where: r.id in ^ids, select: %{res_id: r.id, kind: r.kind})
      |> Enum.map(&Map.merge(&1, %{purged_at: now, inserted_at: now, updated_at: now}))

    {count, _} = repo.insert_all(Tombstone, rows)
    {:ok, count}
  end
end
