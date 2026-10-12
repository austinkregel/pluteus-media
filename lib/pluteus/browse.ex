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
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.Cover
  alias Pluteus.Catalog.Credit
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Res
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Ingest.Registry, as: IngestRegistry
  alias Pluteus.Presentation.Geometry
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
          borne: %{Ecto.UUID.t() => Ecto.UUID.t()},
          geometry: %{Ecto.UUID.t() => Geometry.t()},
          formats: %{Ecto.UUID.t() => String.t()},
          dates: %{Ecto.UUID.t() => String.t()},
          members: %{Ecto.UUID.t() => non_neg_integer()},
          credited: %{Ecto.UUID.t() => [String.t()]},
          covers: %{Ecto.UUID.t() => Ecto.UUID.t()},
          labels: %{String.t() => String.t()},
          agents: %{Ecto.UUID.t() => atom()},
          total: non_neg_integer(),
          catalogue: non_neg_integer(),
          bytes: non_neg_integer(),
          first_acquired: DateTime.t() | nil,
          uncredited: non_neg_integer(),
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
    # §14.3 makes a mode selecting on consumption the requesting principal's own, so the
    # query carries whose it is before anything is selected or counted against it.
    query = %{query | principal_id: principal_id}

    entries = Entries.ids(query, limit)
    figures = figures(query)
    facets = Counts.for_query(query, figures.total)
    borne = borne(entries)

    %{
      labels: labelled(facets, profile),
      agents: kinded(facets),
      query: query,
      entries: entries,
      names: named(entries, profile),
      categories: categorised(entries),
      borne: borne,
      geometry: Geometry.for_res(Map.values(borne)),
      formats: formatted(entries),
      dates: dated(entries),
      members: membered(entries),
      credited: credited(entries, profile),
      covers: Cover.for_works(entries),
      total: figures.total,
      catalogue: figures.catalogue,
      bytes: bytes(figures.bytes),
      first_acquired: figures.first_acquired,
      uncredited: figures.uncredited,
      facets: facets,
      unfinished: Unfinished.for_principal(principal_id)
    }
  end

  # Every figure the surface states, in one pass.
  #
  # Three of them count holdings, and arriving at the holdings is what costs: it reads the
  # recycle bin, the aggregating relation, the part relation and the companion kinds, none
  # of which depends on which figure is being taken. Asked one at a time that work is
  # repeated per figure, so they are asked together and each is the condition it counts
  # under.
  #
  # Two count the query and the third counts the mode unnarrowed — the figure a narrowed
  # surface says it is a part of. The narrowing stays in what the query counts over rather
  # than becoming a fourth condition, so a facet leaving a tenth of the holdings leaves a
  # tenth of the rows to count. Sharing one derivation between the two sets instead was
  # measured and is slower: it buys the unnarrowed surface three milliseconds and costs a
  # narrowed one eighteen, because what the sharing needs is a barrier the narrowing then
  # cannot be pushed through.
  #
  # The last two count other things: the bytes on the disk and the earliest arrival. They
  # ride along because they are figures of the same surface and a round trip of their own
  # costs more than stating them here does.
  defp figures(%Query{} = query) do
    whole = from w in Entries.selected(Query.unnarrowed(query)), select: count(w.id)
    credited = Entries.credited_works()
    disk = from a in Asset, select: sum(a.size)
    earliest = from a in Acquisition, select: min(a.inbox_released_at)

    Repo.one(
      from [work: w] in Entries.narrow(Entries.selected(query), query),
        select: %{
          total: count(w.id),
          uncredited: filter(count(w.id), w.id not in subquery(credited)),
          catalogue: subquery(whole),
          bytes: subquery(disk),
          first_acquired: subquery(earliest)
        }
    )
  end

  # What is held, which is the bytes of every asset kept rather than of what arrived: a
  # re-encoded master and the original it was made from are both on the disk, and a
  # figure that counted one of them would not be the size of the thing it names.
  # Postgres sums a bigint into a numeric, which arrives as a decimal, so the figure is
  # brought back to a count of bytes rather than divided as one and raising.
  defp bytes(nil), do: 0
  defp bytes(%Decimal{} = total), do: Decimal.to_integer(total)
  defp bytes(total) when is_integer(total), do: total

  # A res carrying no nomen this profile may see is absent from resolution rather than
  # present with nothing, and a work carries a name at commit, so a row with
  # no name here is a broken invariant and not a case to render around.
  defp named([], _profile), do: %{}

  defp named(entries, profile) do
    for {id, nomen} <- Resolution.resolve_many(entries, profile),
        into: %{},
        do: {id, nomen.nomen_string}
  end

  # A facet value that is an identifier reaches a person as the name it is known by. The
  # names come through resolution under the requesting principal's own profile, for the
  # same reason a row's does.
  defp labelled(facets, profile) do
    case facets["person"] do
      {:available, [_one | _more] = values} ->
        ids = Enum.map(values, &elem(&1, 0))

        for {id, nomen} <- Resolution.resolve_many(ids, profile),
            into: %{},
            do: {id, nomen.nomen_string}

      _nothing_identified ->
        %{}
    end
  end

  # Which of spec-01 §3.1's three agent kinds each credited agent is, which is what its
  # address is built from: an artist, a person and a collective agent are three paths.
  # Only where the axis offers somebody, so a surface that credits nobody pays nothing.
  defp kinded(facets) do
    case facets["person"] do
      {:available, [_one | _more] = values} ->
        ids = Enum.map(values, &elem(&1, 0))

        Map.new(Repo.all(from r in Res, where: r.id in ^ids, select: {r.id, r.kind}))

      _nothing_identified ->
        %{}
    end
  end

  # Who a holding is by. The first fact a person looks for in a list of music, and a
  # holding carrying none says nothing rather than saying so twice — the kind is already
  # beside it.
  #
  # Credits are ordered by role and position, which is the order placement wrote them in,
  # so an album artist leads the track artists it gathers.
  defp credited([], _profile), do: %{}

  defp credited(entries, profile) do
    credits =
      Repo.all(
        from c in Credit,
          where: c.work_id in ^entries,
          where: not is_nil(c.agent_id),
          order_by: [c.role, c.position],
          select: {c.work_id, c.agent_id}
      )

    named =
      credits
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> Resolution.resolve_many(profile)

    credits
    |> Enum.group_by(&elem(&1, 0), &named[elem(&1, 1)])
    |> Map.new(fn {work_id, nomens} ->
      {work_id, nomens |> Enum.reject(&is_nil/1) |> Enum.map(& &1.nomen_string) |> Enum.uniq()}
    end)
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

  # The manifestation an entry is carried by, which is what an image profile is asked
  # for against. A photograph wears no cover: the photograph is the picture, so a grid
  # of them asks the holding itself rather than a companion (§12.2).
  defp borne([]), do: %{}

  defp borne(entries) do
    # One per entry, by identifier, so a work embodied twice answers the same way on
    # every render rather than drawing a different picture each time.
    Repo.all(
      from x in Expression,
        join: e in Embodiment,
        on: e.expression_id == x.id,
        where: x.work_id in ^entries,
        distinct: x.work_id,
        order_by: [x.work_id, e.manifestation_id],
        select: {x.work_id, e.manifestation_id}
    )
    |> Map.new()
  end

  # What a household calls the format of the bytes behind an entry, where every asset
  # under it agrees on one. Two editions of one book resolve to one name and sit beside
  # each other saying the same thing, and this is what tells them apart.
  #
  # Where an entry's assets disagree — a release of FLAC and MP3 — there is no one
  # format to name and the row says nothing rather than naming the first one found.
  defp formatted([]), do: %{}

  defp formatted(entries) do
    Repo.all(
      from w in Expression,
        join: e in Embodiment,
        on: e.expression_id == w.id,
        join: i in DigitalItem,
        on: i.manifestation_id == e.manifestation_id,
        join: a in Asset,
        on: a.digital_item_id == i.id,
        where: w.work_id in ^entries,
        group_by: w.work_id,
        having: count(a.format, :distinct) == 1,
        select: {w.work_id, min(a.format)}
    )
    |> Map.new(fn {id, format} -> {id, IngestRegistry.format_name(format)} end)
  end

  # When each entry was issued, as the container stated it. The earliest where a work
  # answers for several, because a reissue states a date of its own and what a person
  # looking at a list wants beside the name is when the thing first came out.
  defp dated([]), do: %{}

  defp dated(entries) do
    Repo.all(
      from d in subquery(Entries.dates()),
        where: d.res_id in ^entries,
        group_by: d.res_id,
        select: {d.res_id, min(d.value)}
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
