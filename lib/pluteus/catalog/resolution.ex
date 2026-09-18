defmodule Pluteus.Catalog.Resolution do
  @moduledoc """
  Chooses the one name a res is shown under, at the render boundary.

  The ordering is total, so the same res and profile yield the same nomen on
  every call. Preferences that tie fall through to the identifier, which never
  changes — without that last step the same item could appear under different
  labels between two page loads.

  Nothing here writes. §7.4 confines resolution to output, leaving search free
  to match against every name a res carries rather than only the chosen one.

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
  Picks one nomen from a set, independently of the order they arrive in.

  Separated from the query because that independence is the whole of §7.4's
  determinism requirement, and a database returns rows in whatever order suits
  its plan. Every preference can tie; the identifier cannot, so the ordering is
  total and the same set always yields the same answer.
  """
  @spec choose([Nomen.t()], Profile.t()) :: Nomen.t()
  def choose(nomens, %Profile{} = profile) do
    Enum.min_by(nomens, &rank(&1, profile))
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
  defp rank(nomen, profile) do
    {
      personal_before_household(nomen),
      Enum.find_index(Nomen.provenance_rank(), &(&1 == nomen.provenance)),
      language_match(nomen, profile),
      nomen.id
    }
  end

  defp personal_before_household(%Nomen{assigner_id: nil}), do: 1
  defp personal_before_household(_nomen), do: 0

  defp language_match(%Nomen{language: language}, %Profile{language: language}), do: 0
  defp language_match(_nomen, _profile), do: 1
end
