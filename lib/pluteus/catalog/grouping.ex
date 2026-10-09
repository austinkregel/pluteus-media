defmodule Pluteus.Catalog.Grouping do
  @moduledoc """
  A res carrying ordered members, and the order it carries them in ([spec-10] §8.3).

  A release and its tracks, a serial manifestation and its episodes, an anthology, a
  photograph album, a correspondence file: each is one res carrying ordered members, and
  what differs is which relation the order lives on.

  ## One relation carries the order, and it is never the other

  §8.3 gives two: the whole-part positions, and an aggregation's arrangement. §8.3
  forbids presenting one relation's positions as the other's, so which answers is decided
  by which the grouping actually has, in two clauses with nothing mixing them. A release
  and a serial carry parts; an aggregate the household composed carries an arrangement
  and no parts.

  spec-01 §5.3 forbids whole-part between an aggregating work and what it aggregates, and
  §5.4 forbids it between a serial work and its episodes, which is why the order is read
  from the manifestations rather than from the works.

  ## The members are the leaves, because containment is deeper than one level

  A release's manifestation carries its media and each medium carries its tracks, so the
  members are two levels down and the order is the walk rather than one position. What
  the walk returns is what carries nothing further: the tracks, not the discs. A person
  asking for a release means its tracks, and the disc is how they are grouped rather than
  a thing of its own to reach.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Catalog.Aggregation
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.ManifestationPart
  alias Pluteus.Repo

  @doc """
  The works a grouping carries, in the order the relation carrying it puts them, or an
  empty list where the res carries no members.

  What a page listing the members links to, since a browse entry is a work.
  """
  @spec members_of(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def members_of(work_id) do
    case member_manifestations_of(work_id) do
      [] -> by_arrangement(work_id)
      manifestations -> works_embodying(manifestations)
    end
  end

  @doc """
  The manifestations a grouping carries, in the same order.

  What a queue names, because a position and an extent are recorded against the
  manifestation ([spec-01] §8.4) and the OpenSubsonic surface's song is the same res. A
  member reached this way needs no expression selected for it: the relation carrying the
  order already named one manifestation, and §8.1's selection is about which expression
  of a work to give where the work has several.
  """
  @spec member_manifestations_of(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def member_manifestations_of(work_id) do
    case own_manifestation(work_id) do
      nil -> []
      manifestation_id -> leaves_under(manifestation_id)
    end
  end

  @doc """
  The grouping a work is a member of, or nil where it is a member of none.

  What a surface needs to answer §12.4's question — whether a next member exists — and
  to fill a queue from a member rather than from the whole.
  """
  @spec grouping_of(Ecto.UUID.t()) :: Ecto.UUID.t() | nil
  def grouping_of(work_id) do
    case aggregating(work_id) do
      nil -> enclosing(work_id)
      aggregating -> aggregating
    end
  end

  # The manifestation a work is the work *of*: the one it embodies that is no part of
  # another. A release embodies its media as well as the release itself, and the media are
  # parts, so taking any embodiment would make a release the work of its own disc.
  defp own_manifestation(work_id) do
    Repo.one(
      from b in Embodiment,
        join: x in Expression,
        on: x.id == b.expression_id,
        where: x.work_id == ^work_id,
        where: b.manifestation_id not in subquery(from p in ManifestationPart, select: p.part_id),
        order_by: b.manifestation_id,
        limit: 1,
        select: b.manifestation_id
    )
  end

  # Depth-first in position order, keeping what carries nothing further. A manifestation
  # with no parts is not a member of itself, which is what makes a holding with no
  # structure carry no members rather than carrying one.
  defp leaves_under(manifestation_id) do
    manifestation_id |> parts_of() |> Enum.flat_map(&leaf_or_deeper/1)
  end

  # A part carrying parts of its own contributes those rather than itself, which is what
  # keeps a release's discs out of its members.
  defp leaf_or_deeper(manifestation_id) do
    case leaves_under(manifestation_id) do
      [] -> [manifestation_id]
      deeper -> deeper
    end
  end

  defp parts_of(whole_id) do
    Repo.all(
      from p in ManifestationPart,
        where: p.whole_id == ^whole_id,
        order_by: [asc_nulls_last: p.position, asc: p.part_id],
        select: p.part_id
    )
  end

  # Each member manifestation's own work, in the order the manifestations came in. A
  # manifestation embodies one expression where placement wrote it, and the order is the
  # walk's rather than the query's, so it is restored here.
  defp works_embodying(manifestation_ids) do
    works =
      Map.new(
        Repo.all(
          from b in Embodiment,
            join: x in Expression,
            on: x.id == b.expression_id,
            where: b.manifestation_id in ^manifestation_ids,
            select: {b.manifestation_id, x.work_id}
        )
      )

    for manifestation_id <- manifestation_ids,
        work_id = works[manifestation_id],
        do: work_id
  end

  # §8.3's third row: an aggregate with no whole-part structure is ordered by the
  # aggregation's own arrangement.
  defp by_arrangement(work_id) do
    Repo.all(
      from a in Aggregation,
        join: aggregating in Expression,
        on: aggregating.id == a.aggregating_expression_id,
        join: aggregated in Expression,
        on: aggregated.id == a.aggregated_expression_id,
        where: aggregating.work_id == ^work_id,
        order_by: [asc_nulls_last: a.arrangement, asc: aggregated.id],
        select: aggregated.work_id
    )
  end

  defp aggregating(work_id) do
    Repo.one(
      from a in Aggregation,
        join: aggregated in Expression,
        on: aggregated.id == a.aggregated_expression_id,
        join: aggregating in Expression,
        on: aggregating.id == a.aggregating_expression_id,
        where: aggregated.work_id == ^work_id,
        order_by: aggregating.work_id,
        limit: 1,
        select: aggregating.work_id
    )
  end

  # Up the whole-part chain to the outermost manifestation, whose work is the grouping.
  # A serial's episodes reach their serial this way: §5.4 connects the works only by
  # inspiration, so the containment is at manifestation level and nowhere else.
  defp enclosing(work_id) do
    with manifestation_id when is_binary(manifestation_id) <- any_manifestation(work_id),
         outermost when outermost != manifestation_id <- outermost(manifestation_id) do
      Repo.one(
        from b in Embodiment,
          join: x in Expression,
          on: x.id == b.expression_id,
          where: b.manifestation_id == ^outermost,
          where: x.work_id != ^work_id,
          order_by: x.work_id,
          limit: 1,
          select: x.work_id
      )
    else
      _no_enclosing_manifestation -> nil
    end
  end

  defp any_manifestation(work_id) do
    Repo.one(
      from b in Embodiment,
        join: x in Expression,
        on: x.id == b.expression_id,
        where: x.work_id == ^work_id,
        order_by: b.manifestation_id,
        limit: 1,
        select: b.manifestation_id
    )
  end

  defp outermost(manifestation_id) do
    case Repo.one(
           from p in ManifestationPart,
             where: p.part_id == ^manifestation_id,
             order_by: p.whole_id,
             limit: 1,
             select: p.whole_id
         ) do
      nil -> manifestation_id
      whole -> outermost(whole)
    end
  end
end
