defmodule Pluteus.Browse.Search do
  @moduledoc """
  Which holdings a term reaches, through which of their names, and in what order
  ([spec-10] §9.5, §6.2, §6.4).

  ## Every nomen, and the holding it belongs to

  §9.5 requires the search to match every nomen a res carries, and spec-01 §7.4 leaves
  search free to do so while confining resolution to output. A browse surface lists
  holdings, though, and the names a person searches for are as often a track's or an
  artist's as the holding's own. So a term reaches an entry through any res the entry
  answers for:

    * the work itself, its expressions and the manifestations they embody — one holding
      named at each level;
    * a work its expression aggregates — a track, which reaches the release that
      presents it;
    * an agent a credit names — the artist, which reaches what they are credited on.

  Each reach records the nomen it went through, which is what lets a result say which
  name matched where it is not the one shown (§6.2's third slot, criterion 13).

  Only names the profile may see are matched, through the same rule resolution reads
  (`Pluteus.Catalog.Resolution.assigned_for/2`): a member's personal label for a holding
  is that member's, and a search that matched it for anybody else would both find the
  holding by it and show it to them.

  Matching is case-insensitive containment. Ranking is spec-09's, and nothing here ranks:
  it decides what is reached, and §6.4 decides the order.
  """

  import Ecto.Query

  alias Pluteus.Catalog.Aggregation
  alias Pluteus.Catalog.Credit
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Catalog.Work
  alias Pluteus.Lifecycle.RecycledRes
  alias Pluteus.Lifecycle.Tombstone
  alias Pluteus.Repo
  alias Pluteus.Surfaces.Registry, as: Surfaces

  @typedoc """
  The order a list of results is in, which the surface states (§6.4): every result by
  its ordering nomen, every result by its resolved one, or each by the first of those it
  carries.
  """
  @type basis :: :ordering | :resolved | :mixed

  @doc """
  Each work a term reaches, with the nomen it was reached through, as a query selecting
  `%{work_id, nomen_id}`. A work reached through several names appears once per name.

  Not narrowed to browse entries: what a surface lists is decided by the selection this
  is read inside, so a track's own work reached here drops out there and the release it
  reached through its aggregation stays.
  """
  @spec reaching(String.t(), Profile.t()) :: Ecto.Query.t()
  def reaching(term, %Profile{} = profile) do
    matching = matching(term, profile)

    own =
      from m in subquery(matching),
        join: w in Work,
        on: w.id == m.res_id,
        select: %{work_id: w.id, nomen_id: m.id}

    expressed =
      from m in subquery(matching),
        join: x in Expression,
        on: x.id == m.res_id,
        select: %{work_id: x.work_id, nomen_id: m.id}

    embodied =
      from m in subquery(matching),
        join: e in Embodiment,
        on: e.manifestation_id == m.res_id,
        join: x in Expression,
        on: x.id == e.expression_id,
        select: %{work_id: x.work_id, nomen_id: m.id}

    gathered =
      from m in subquery(matching),
        join: tx in Expression,
        on: tx.work_id == m.res_id,
        join: a in Aggregation,
        on: a.aggregated_expression_id == tx.id,
        join: ax in Expression,
        on: ax.id == a.aggregating_expression_id,
        select: %{work_id: ax.work_id, nomen_id: m.id}

    credited =
      from m in subquery(matching),
        join: c in Credit,
        on: c.agent_id == m.res_id,
        left_join: x in Expression,
        on: x.id == c.expression_id,
        select: %{work_id: coalesce(c.work_id, x.work_id), nomen_id: m.id}

    own
    |> union_all(^expressed)
    |> union_all(^embodied)
    |> union_all(^gathered)
    |> union_all(^credited)
  end

  @doc """
  The works a term reaches, for a selection to be narrowed by.
  """
  @spec works(String.t(), Profile.t()) :: Ecto.Query.t()
  def works(term, %Profile{} = profile) do
    from r in subquery(reaching(term, profile)), where: not is_nil(r.work_id), select: r.work_id
  end

  @doc """
  The names each of a page's results was reached through, keyed by work.
  """
  @spec matched([Ecto.UUID.t()], String.t(), Profile.t()) :: %{Ecto.UUID.t() => [String.t()]}
  def matched([], _term, _profile), do: %{}

  def matched(work_ids, term, %Profile{} = profile) do
    Repo.all(
      from r in subquery(reaching(term, profile)),
        join: n in Nomen,
        on: n.id == r.nomen_id,
        where: r.work_id in ^work_ids,
        distinct: true,
        select: {r.work_id, n.nomen_string}
    )
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {work_id, names} -> {work_id, Enum.sort(names)} end)
  end

  @doc """
  The name a result is said to have matched through, or nil where the name it is shown by
  is one of them (§6.2).
  """
  @spec matched_through([String.t()], String.t()) :: String.t() | nil
  def matched_through(names, shown) do
    if shown in names, do: nil, else: List.first(names)
  end

  @doc """
  Results in §6.4's order, with the basis the surface states.

  A result carrying an ordering nomen is ordered by it, and one carrying none by its
  resolved nomen. No ingest path writes an ordering nomen, so the household's results are
  ordered by name and say so; the clause exists so a household that records one gets it.
  Ties fall to the identifier, so one set of results has one order.
  """
  @spec ordered([Ecto.UUID.t()], Profile.t()) :: {[Ecto.UUID.t()], basis()}
  def ordered([], _profile), do: {[], :resolved}

  def ordered(work_ids, %Profile{} = profile) do
    names = Resolution.resolve_many(work_ids, profile)
    orderings = orderings(work_ids, profile)

    sorted =
      Enum.sort_by(work_ids, fn id ->
        key = orderings[id] || Map.fetch!(names, id).nomen_string
        {String.downcase(key), id}
      end)

    {sorted, basis(map_size(orderings), length(work_ids))}
  end

  defp basis(0, _results), do: :resolved
  defp basis(results, results), do: :ordering
  defp basis(_some, _results), do: :mixed

  # The ordering nomen each result carries that the profile may see. Where one carries
  # several, the least of them, so the order does not depend on the order rows arrive in.
  defp orderings(work_ids, profile) do
    from(n in Nomen,
      where: n.res_id in ^work_ids,
      where: n.scheme == ^Surfaces.ordering_scheme(),
      group_by: n.res_id,
      select: {n.res_id, min(n.nomen_string)}
    )
    |> Resolution.assigned_for(profile)
    |> Repo.all()
    |> Map.new()
  end

  # The nomens containing the term that the profile may see and the catalog holds: a
  # nomen is a res, so a recycled or purged one matches nothing.
  defp matching(term, profile) do
    from(n in Nomen,
      where: ilike(n.nomen_string, ^pattern(term)),
      where: n.id not in subquery(from b in RecycledRes, select: b.res_id),
      where: n.id not in subquery(from t in Tombstone, select: t.res_id),
      select: %{id: n.id, res_id: n.res_id}
    )
    |> Resolution.assigned_for(profile)
  end

  # Containment, with the term's own wildcard characters taken literally: a person
  # searching for "100%" is looking for those four characters.
  defp pattern(term) do
    escaped = String.replace(term, ["\\", "%", "_"], &("\\" <> &1))

    "%" <> escaped <> "%"
  end
end
