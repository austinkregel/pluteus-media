defmodule Pluteus.Browse.Entries do
  @moduledoc """
  What a browse surface is a list of.

  A res is a browse entry where no other res in the catalog presents it, and a res is
  presented where an aggregating work selects its expression or its manifestation is a
  part under a whole-part relation. So a release carries the entry and its tracks do not,
  and a complete serial manifestation carries the entry and its episodes do not.

  ## The entry is the work

  That rule is about a res, and by its letter a work, the expression realizing it and the
  manifestation embodying it are each an entry, since none of the three is presented by
  the other two. Counting all three would count one holding three times, so the work
  is what carries the entry here. That is where the evidence is: `work-category` is
  recorded on the work, which is the scheme every category facet turns on, and
  `Pluteus.Catalog.works_of_many/1` already maps any res to its work in a bounded number
  of queries, so a res reached from anywhere else can be brought back to its entry.

  Read through the chain, a work is an entry where no expression of it is aggregated by
  another, and it embodies at least one manifestation that is no part of another. Both
  halves are needed and neither alone is right: a release work embodies its media as
  well as the release manifestation, and the media *are* parts, so asking that none of
  its manifestations be a part would present a release by its own discs.

  ## The category has to be the effective one

  `Pluteus.Catalog.category_of/2` prefers a local assignment to an automatic one and an
  automatic one to a seed, so a work corrected by a member carries two category rows.
  Matching either would put that work under two categories, and the facet counts would
  stop summing to the total, which is a false statement about what selecting one does. So
  narrowing and
  counting share one subquery that takes the effective row per work, and neither is free
  to decide it separately.
  """

  import Ecto.Query

  alias Pluteus.Browse.Query
  alias Pluteus.Catalog.Aggregation
  alias Pluteus.Catalog.Category
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.ManifestationPart
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Res
  alias Pluteus.Catalog.Work
  alias Pluteus.Ingest.Place
  alias Pluteus.Ingest.Registry
  alias Pluteus.Lifecycle.RecycledRes
  alias Pluteus.Lifecycle.Tombstone
  alias Pluteus.Repo

  @doc """
  Every work a browse surface may list, before any narrowing.

  A recycled or purged work is not listed. That rule is the same one an entity page
  answers for, and it lives here rather than beside each surface so there is one
  statement of what the catalog currently holds.
  """
  @spec base() :: Ecto.Query.t()
  def base do
    from w in Work,
      as: :work,
      where: w.id not in subquery(from b in RecycledRes, select: b.res_id),
      where: w.id not in subquery(from t in Tombstone, select: t.res_id),
      where: not exists(aggregated()),
      where: exists(embodies_a_whole()),
      where: not exists(companion())
  end

  # A companion is a holding in its own right and has an address of its own, but it is
  # never *presented* as one: the cover art of a release belongs to the release, and a
  # list of what the household holds that put it beside the release would be listing the
  # same thing twice. It carries no category glyph and no class colour for the same
  # reason, so there is nothing to draw it as.
  defp companion do
    from c in Category,
      where: c.res_id == parent_as(:work).id,
      where: c.scheme == ^Place.category_scheme(),
      where: c.value in ^Registry.companion_kinds(),
      select: 1
  end

  @doc """
  The works a query holds, narrowed by every facet it carries.
  """
  @spec narrow(Ecto.Query.t(), Query.t()) :: Ecto.Query.t()
  def narrow(query, %Query{} = browse) do
    Enum.reduce(
      Query.narrowings(browse) |> Enum.group_by(&elem(&1, 0), &elem(&1, 1)),
      query,
      &on/2
    )
  end

  @doc """
  How many works a query holds.
  """
  @spec count(Query.t()) :: non_neg_integer()
  def count(%Query{} = browse) do
    Repo.aggregate(from(w in narrow(base(), browse), select: w.id), :count)
  end

  @doc """
  The identifiers a query holds, in a stable order, bounded.
  """
  @spec ids(Query.t(), pos_integer()) :: [Ecto.UUID.t()]
  def ids(%Query{} = browse, limit) do
    base()
    |> narrow(browse)
    |> order_by([work: w], w.id)
    |> limit(^limit)
    |> select([work: w], w.id)
    |> Repo.all()
  end

  @doc """
  The effective category of each work: the row its provenance makes authoritative, one
  per work, which both a narrowing and a count read.
  """
  @spec effective_categories() :: Ecto.Query.t()
  def effective_categories do
    ranks = Enum.map(Nomen.provenance_rank(), &Atom.to_string/1)

    from c in Category,
      where: c.scheme == ^Place.category_scheme(),
      distinct: c.res_id,
      order_by: [
        asc: c.res_id,
        asc: fragment("array_position(?::text[], ?::text)", ^ranks, c.provenance)
      ],
      select: %{res_id: c.res_id, value: c.value}
  end

  @doc """
  The same selection with each work's effective category beside it, bound as `:category`.

  Both a narrowing and a count read the category through this, so neither is free to
  decide which of a corrected work's rows is authoritative.
  """
  @spec with_category(Ecto.Query.t()) :: Ecto.Query.t()
  def with_category(query) do
    from [work: w] in query,
      join: c in subquery(effective_categories()),
      as: :category,
      on: c.res_id == w.id
  end

  @doc """
  The axes this release can narrow on. The rest are named and inert.
  """
  @spec narrowable_axes() :: [String.t()]
  def narrowable_axes, do: ["category"]

  # Disjunctive within the axis: a work matching any of the values is held.
  defp on({"category", values}, query) do
    from [category: c] in with_category(query), where: c.value in ^values
  end

  defp on({axis, _values}, _query) do
    raise ArgumentError,
          "#{inspect(axis)} is not a facet axis this release narrows on. " <>
            "The axes it narrows on are: #{Enum.join(narrowable_axes(), ", ")}."
  end

  # The first presenting relation, as an expression of this work being selected by an
  # aggregating one.
  defp aggregated do
    from x in Expression,
      join: a in Aggregation,
      on: a.aggregated_expression_id == x.id,
      where: parent_as(:work).id == x.work_id,
      select: 1
  end

  # The second, read the other way round: the work is an entry where something it
  # embodies is nobody's part, rather than where nothing it embodies is a part.
  defp embodies_a_whole do
    from x in Expression,
      join: e in Embodiment,
      on: e.expression_id == x.id,
      where: parent_as(:work).id == x.work_id,
      where: e.manifestation_id not in subquery(from p in ManifestationPart, select: p.part_id),
      select: 1
  end

  @doc """
  Whether a res is live, which is what every browse surface and every entity page means
  by the catalog currently holding something.
  """
  @spec live?(Ecto.UUID.t()) :: boolean()
  def live?(res_id) do
    Repo.exists?(
      from r in Res,
        where: r.id == ^res_id,
        where: r.id not in subquery(from b in RecycledRes, select: b.res_id),
        where: r.id not in subquery(from t in Tombstone, select: t.res_id)
    )
  end
end
