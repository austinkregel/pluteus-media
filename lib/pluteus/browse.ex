defmodule Pluteus.Browse do
  import Ecto.Query

  @moduledoc """
  What a browse surface needs to render, assembled in one call.

  Its own context rather than part of `Pluteus.Catalog`, because it reaches across
  catalog, custody, ingest and consumption: what is held, what is overdue for
  verification, what is undecided, and what the requesting principal has looked at. None
  of those belong to the others.

  ## One call, a fixed number of queries

  Every facet value's count is recomputed on every render, so the cost of a
  render is the thing most likely to decide whether the surface is usable at all. A
  surface that asked per facet value, or per row, would be correct on a household of
  three holdings and unusable on one of thirty thousand — and the difference would not
  show up in any test of what it displays.

  So the number of queries a gateway costs is fixed: it does not grow with the catalog,
  with how many values a facet offers, or with how many rows are shown. A test asserts
  that by counting the queries against a small catalog and against a larger one, which is
  how the property is held rather than claimed.
  """

  alias Pluteus.Browse.Counts
  alias Pluteus.Browse.Entries
  alias Pluteus.Browse.Query
  alias Pluteus.Browse.Unfinished
  alias Pluteus.Catalog.Aggregation
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Repo

  @typedoc """
  A rendered surface's own facts: the query it is showing, the entries it holds, how many
  there are in total, what each facet value would leave held, and the doors into
  unfinished work.
  """
  @type surface :: %{
          query: Query.t(),
          entries: [Ecto.UUID.t()],
          names: %{Ecto.UUID.t() => String.t()},
          categories: %{Ecto.UUID.t() => String.t()},
          members: %{Ecto.UUID.t() => non_neg_integer()},
          total: non_neg_integer(),
          catalogue: non_neg_integer(),
          facets: %{String.t() => Counts.facet()},
          unfinished: [Unfinished.door()]
        }

  @doc """
  Everything a browse surface renders from.

  `entries` is bounded by `limit` because a surface shows a page and not a catalog. The
  total beside it is of the whole query and `catalogue` is of the mode with nothing
  narrowing it, so a narrowed surface can say how much of the whole it is showing without
  reading either.

  The names come through resolution under the requesting principal's own profile, which
  is what keeps a member's private label for a holding from being shown to another as its
  name. They are resolved for the page rather than per row, which is the same reason the
  counts are: a query per row is a cost that grows.
  """
  @spec surface(Query.t(), Ecto.UUID.t(), Profile.t(), pos_integer()) :: surface()
  def surface(%Query{} = query, principal_id, %Profile{} = profile, limit \\ 60) do
    entries = Entries.ids(query, limit)

    %{
      query: query,
      entries: entries,
      names: named(entries, profile),
      categories: categorised(entries),
      members: membered(entries),
      total: Entries.count(query),
      catalogue: Entries.count(Query.unnarrowed(query)),
      facets: Counts.for_query(query),
      unfinished: Unfinished.for_principal(principal_id)
    }
  end

  # A res carrying no nomen this profile may see is absent from resolution rather than
  # present with nothing, and a work carries a name at commit, so a row with
  # no name here is a broken invariant and not a case to render around.
  defp named([], _profile), do: %{}

  defp named(entries, profile) do
    for {id, nomen} <- Resolution.resolve_many(entries, profile),
        into: %{},
        do: {id, nomen.nomen_string}
  end

  # The effective category, through the subquery a narrowing and a count also read.
  defp categorised([]), do: %{}

  defp categorised(entries) do
    Repo.all(
      from c in subquery(Entries.effective_categories()),
        where: c.res_id in ^entries,
        select: {c.res_id, c.value}
    )
    |> Map.new()
  end

  # How many expressions an entry aggregates: a release's tracks.
  defp membered([]), do: %{}

  defp membered(entries) do
    Repo.all(
      from x in Expression,
        join: a in Aggregation,
        on: a.aggregating_expression_id == x.id,
        where: x.work_id in ^entries,
        group_by: x.work_id,
        select: {x.work_id, count(a.aggregated_expression_id)}
    )
    |> Map.new()
  end
end
