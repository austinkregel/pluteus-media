defmodule Pluteus.Catalog.Resolution do
  @moduledoc """
  Chooses the one name a res is shown under, at the render boundary.

  The ordering is total, so the same res and profile yield the same nomen on
  every call. Preferences that tie fall through to the identifier, which never
  changes — without that last step the same item could appear under different
  labels between two page loads.

  Nothing here writes. §7.4 confines resolution to output, leaving search free
  to match against every name a res carries rather than only the chosen one.

  **Language narrows the candidates before the ordering chooses among them**, per
  [spec-10] §6.1, which adopts [IIIF-PRES] §4.4's selection as a filter. That
  inverts the precedence §7.4 describes, where a personal nomen comes first and
  language is a later tiebreak: a name in a language the person cannot read is
  not a better answer for being personal.

  Two res linked as one thing (§7.5) resolve over the names of both, so a
  household row and the seed a later release ships for the same concept answer
  alike, and the local name wins by the rule that makes a correction outrank a
  shipped name.

  A name deleted on its own is not shown (§14). A name that went into the
  recycle bin with the res it names still is, because the bin has to label what
  it holds. The same holds across a §7.5 link: while one of the pair is in the
  bin, the other answers for itself.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Catalog.Association
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Profile
  alias Pluteus.Lifecycle.RecycledRes
  alias Pluteus.Repo

  defmodule NoNomenError do
    @moduledoc """
    Raised when a res carries no name resolution is permitted to return.
    """
    defexception [:message]
  end

  @doc """
  The name to show for one res.

  Raises when the res carries no nomen. §7.4 requires resolution to always
  return one, so the absence is a broken invariant rather than a case for the
  caller to handle.
  """
  @spec resolve(Ecto.UUID.t(), Profile.t()) :: Nomen.t()
  def resolve(res_id, %Profile{} = profile) do
    case resolve_many([res_id], profile) do
      %{^res_id => nomen} ->
        nomen

      _no_match ->
        raise NoNomenError,
          message: "res #{res_id} carries no nomen visible to this profile"
    end
  end

  @doc """
  The name to show for each of many res, as a map keyed by res identifier.

  A res carrying no visible nomen is absent from the result rather than present
  with a nil value.
  """
  @spec resolve_many([Ecto.UUID.t()], Profile.t()) :: %{Ecto.UUID.t() => Nomen.t()}
  def resolve_many(res_ids, %Profile{} = profile) do
    groups = same_thing_groups(res_ids)

    by_res =
      groups
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()
      |> visible(profile)
      |> Repo.all()
      |> Enum.group_by(& &1.res_id)

    for {res_id, group} <- groups,
        nomens = Enum.flat_map(group, &Map.get(by_res, &1, [])),
        nomens != [],
        into: %{} do
      {res_id, choose(nomens, profile)}
    end
  end

  @doc """
  The nomens each of many res carries that a profile may see, keyed by res
  identifier. A res carrying none is absent.

  §7.3 makes a non-null assigner a name specific to that agent, so a profile sees
  the household's shared vocabulary and its own person's variants on it, and
  nobody else's. One person's word for a thing stays with that person.

  Unlike `resolve_many/2` this does not follow §7.5's links: these are the nomens
  the res itself carries, which is what a representation reports.
  """
  @spec visible_many([Ecto.UUID.t()], Profile.t()) :: %{Ecto.UUID.t() => [Nomen.t()]}
  def visible_many(res_ids, %Profile{} = profile) do
    res_ids
    |> visible(profile)
    |> Repo.all()
    |> Enum.group_by(& &1.res_id)
  end

  @doc """
  Picks one nomen from a set, independently of the order they arrive in.

  Separated from the query because that independence is the whole of §7.4's
  determinism requirement, and a database returns rows in whatever order suits
  its plan. Every preference can tie; the identifier cannot, so the ordering is
  total and the same set always yields the same answer.

  [spec-10] §6.1's language filter narrows the set first, and the ordering chooses
  within what survives.
  """
  @spec choose([Nomen.t()], Profile.t()) :: Nomen.t()
  def choose(nomens, %Profile{} = profile) do
    nomens |> candidates(profile) |> Enum.min_by(&rank/1)
  end

  # [spec-10] §6.1's four clauses, in that order.
  #
  # A profile naming no language narrows nothing: a nil language expresses no
  # preference and does not ask for names that are themselves untagged (Profile).
  defp candidates(nomens, %Profile{language: nil}), do: nomens

  defp candidates(nomens, %Profile{language: language}) do
    {tagged, untagged} = Enum.split_with(nomens, & &1.language)
    matching = Enum.filter(tagged, &(&1.language == language))

    cond do
      tagged == [] -> nomens
      matching != [] -> matching
      untagged == [] -> one_language(tagged)
      true -> untagged
    end
  end

  # Clause 3, which applies only where every candidate carries a language. Clause
  # 4 takes the untagged names wherever any exist, which is the household's
  # commonest shape because §7.2 leaves its own vocabulary deliberately untagged.
  #
  # [IIIF-PRES] leaves this choice of language to the client. §6.1 does not,
  # because §7.4 requires the same res and profile to resolve alike across calls:
  # the language is that of the nomen the ordering would select, so the choice is
  # as total as the ordering is.
  defp one_language(tagged) do
    chosen = Enum.min_by(tagged, &rank/1).language

    Enum.filter(tagged, &(&1.language == chosen))
  end

  # One hop only. §7.5 describes a local row and a seed standing for one thing,
  # which is a pair; a chain of them is not a shape the section contemplates.
  defp same_thing_groups(res_ids) do
    links =
      Repo.all(
        from a in Association,
          where: a.refinement == ^Association.same_thing(),
          where: a.subject_id in ^res_ids or a.object_id in ^res_ids,
          select: {a.subject_id, a.object_id}
      )

    involved = Enum.uniq(res_ids ++ Enum.flat_map(links, &Tuple.to_list/1))
    bin = recyclings_holding(involved)

    Map.new(res_ids, fn res_id ->
      linked =
        for {subject_id, object_id} <- links,
            res_id in [subject_id, object_id],
            other <- [subject_id, object_id],
            other != res_id,
            Map.get(bin, other) in [nil, Map.get(bin, res_id)],
            do: other

      {res_id, [res_id | linked]}
    end)
  end

  defp recyclings_holding(res_ids) do
    Map.new(
      Repo.all(
        from r in RecycledRes,
          where: r.res_id in ^res_ids,
          select: {r.res_id, r.recycling_id}
      )
    )
  end

  defp visible(res_ids, profile) do
    from(n in Nomen,
      left_join: own in RecycledRes,
      on: own.res_id == n.id,
      left_join: holder in RecycledRes,
      on: holder.res_id == n.res_id,
      where: n.res_id in ^res_ids,
      where: is_nil(own.res_id) or own.recycling_id == holder.recycling_id
    )
    |> assigned_for(profile)
  end

  # A profile naming no assigner sees household names only. The two clauses are
  # separate because SQL equality against NULL is never true, so one query
  # cannot serve both cases.
  defp assigned_for(query, %Profile{assigner_id: nil}) do
    from n in query, where: is_nil(n.assigner_id)
  end

  defp assigned_for(query, %Profile{assigner_id: assigner_id}) do
    from n in query, where: is_nil(n.assigner_id) or n.assigner_id == ^assigner_id
  end

  # Lower sorts first. Every component is decided by data already on the row, so
  # the comparison is stable across calls and across processes.
  #
  # Language is not a component. [spec-10] §6.1's filter decides the question
  # before the ordering runs, so every candidate reaching here stands in the same
  # relation to the profile's language. As a tiebreak it would also contradict
  # Profile: under a profile naming no language it would score an untagged nomen
  # above a tagged one, preferring the names a nil language does not ask for.
  defp rank(nomen) do
    {
      personal_before_household(nomen),
      Enum.find_index(Nomen.provenance_rank(), &(&1 == nomen.provenance)),
      nomen.id
    }
  end

  defp personal_before_household(%Nomen{assigner_id: nil}), do: 1
  defp personal_before_household(_nomen), do: 0
end
