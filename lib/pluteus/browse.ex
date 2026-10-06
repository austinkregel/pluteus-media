defmodule Pluteus.Browse do
  @moduledoc """
  What a browse surface needs to render, assembled in one call (spec-10 §9.2, §9.3).

  Its own context rather than part of `Pluteus.Catalog`, because it reaches across
  catalog, custody, ingest and consumption: what is held, what is overdue for
  verification, what is undecided, and what the requesting principal has looked at. None
  of those belong to the others.

  ## One call, a fixed number of queries

  §9.3 requires every facet value's count be recomputed on every render, so the cost of a
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

  @typedoc """
  A rendered surface's own facts: the query it is showing, the entries it holds, how many
  there are in total, what each facet value would leave held, and the doors into
  unfinished work.
  """
  @type surface :: %{
          query: Query.t(),
          entries: [Ecto.UUID.t()],
          total: non_neg_integer(),
          facets: %{String.t() => Counts.facet()},
          unfinished: [Unfinished.door()]
        }

  @doc """
  Everything a browse surface renders from.

  `entries` is bounded by `limit` because a surface shows a page and not a catalog; the
  total beside it is of the whole query, so a surface can say *n of total* without
  reading the rest.
  """
  @spec surface(Query.t(), Ecto.UUID.t(), pos_integer()) :: surface()
  def surface(%Query{} = query, principal_id, limit \\ 60) do
    %{
      query: query,
      entries: Entries.ids(query, limit),
      total: Entries.count(query),
      facets: Counts.for_query(query),
      unfinished: Unfinished.for_principal(principal_id)
    }
  end
end
