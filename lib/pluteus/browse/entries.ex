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
  alias Pluteus.Catalog.Association
  alias Pluteus.Catalog.Category
  alias Pluteus.Catalog.Credit
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.ManifestationPart
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Refinements
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

  # A companion has an address of its own but is never presented as a holding: the cover
  # art of a release belongs to the release.
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
  The same selection holding only the works no category row names a kind for.

  A kind is what the first band groups by and the only axis whose vocabulary is closed,
  so a holding without one is in the total and in no kind's figure. Counted through the
  same subquery the band reads, because a count of what the band leaves out has to be
  taken against what the band actually took.
  """
  @spec without_category(Ecto.Query.t()) :: Ecto.Query.t()
  def without_category(query) do
    kinded = from w in with_category(base()), select: w.id

    from [work: w] in query, where: w.id not in subquery(kinded)
  end

  @doc """
  The decade each work's date falls in, from the date its container stated.

  A work carries as many as its manifestations were issued in, which is why this is a
  set rather than a column: a first pressing and a reissue are one work in two decades,
  and both are true.

  The decade is the stated date's first three digits, so a date stated only to the year
  lands in a decade as surely as one stated to the day.
  """
  @spec decades() :: Ecto.Query.t()
  def decades do
    refinement = Refinements.name!("time-of-publication-or-manufacture")

    from m in subquery(answers_for()),
      join: a in Association,
      on: a.subject_id == m.manifestation_id and a.refinement == ^refinement,
      join: n in Nomen,
      on: n.res_id == a.object_id and is_nil(n.assigner_id),
      distinct: true,
      select: %{res_id: m.work_id, value: fragment("substr(?, 1, 3) || '0s'", n.nomen_string)}
  end

  # The manifestations a work answers for: its own, and those of the expressions it
  # aggregates. A date is recorded against the edition it was stated for, so a release
  # read from twelve files carries the date on each track and not on itself — and the
  # release is the entry, so without this the date belongs to nothing anyone can see.
  defp answers_for do
    own =
      from x in Expression,
        join: e in Embodiment,
        on: e.expression_id == x.id,
        select: %{work_id: x.work_id, manifestation_id: e.manifestation_id}

    presented =
      from x in Expression,
        join: g in Aggregation,
        on: g.aggregating_expression_id == x.id,
        join: e in Embodiment,
        on: e.expression_id == g.aggregated_expression_id,
        select: %{work_id: x.work_id, manifestation_id: e.manifestation_id}

    union(own, ^presented)
  end

  @doc """
  The agents each work credits.

  A credit names the work it is a credit on, so a release is reached by the artist it is
  credited to and a track by its own. A track is not an entry — its release presents it —
  so what a browse surface sees through this is the artist a release is credited to.
  """
  @spec creditors() :: Ecto.Query.t()
  def creditors do
    from c in Credit,
      where: not is_nil(c.work_id),
      distinct: true,
      select: %{res_id: c.work_id, value: type(c.agent_id, :string)}
  end

  @doc """
  The axes this release can narrow on. The rest are named and inert.
  """
  @spec narrowable_axes() :: [String.t()]
  defdelegate narrowable_axes(), to: Query

  @doc """
  Each value of an axis with how many of a selection carry it.

  Counted over distinct works, because an axis a work carries twice — two manifestations
  issued in one decade — is one holding to a person looking at the number.
  """
  @spec distribution(String.t(), Ecto.Query.t()) :: %{String.t() => non_neg_integer()}
  def distribution(axis, selection) do
    selection
    |> join(:inner, [work: w], v in subquery(values_of(axis)), as: :value, on: v.res_id == w.id)
    |> group_by([value: v], v.value)
    |> select([work: w, value: v], {v.value, count(w.id, :distinct)})
    |> Repo.all()
    |> Map.new()
  end

  defp values_of("category"), do: effective_categories()
  defp values_of("decade"), do: decades()
  defp values_of("person"), do: creditors()

  # Disjunctive within the axis: a work carrying any of the values is held. Matched
  # through a subquery rather than a join, so a work carrying two of them is held once.
  defp on({axis, values}, query) when axis in ["category", "decade", "person"] do
    carrying =
      from v in subquery(values_of(axis)), where: v.value in ^values, select: v.res_id

    from [work: w] in query, where: w.id in subquery(carrying)
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
