defmodule Pluteus.Matching.Equation do
  @moduledoc """
  Two res matching concludes are one (spec-05 §8.4), equated through spec-03 §8.3's
  operation, reported, and reversible.

  **The operation is the one a member's decision carries out.** Two expressions, or two
  works, cannot be a pair a decision names, so the pair is the manifestations embodying
  them: the earliest-minted of each. It is raised proposing the level the shared
  identifier is at, and decided as proposed by the System principal, which moves the later
  one's children under the earlier one and recycles what it leaves holding nothing.
  Nothing is purged and no asset is deleted.

  **A pair a member has decided distinct is never equated** (criterion 19), and one already
  decided at a level is not decided again.

  **What moved is recorded** — the res kept, the manifestation or expressions moved, where
  from, which aggregates selected what was emptied, and the recycling holding it — and the
  equation is reported as a finding against the holding whose evidence keyed the match,
  since a change to the catalog's shape that nobody is told about is indistinguishable from
  a defect (§8.4). `undo/2` restores exactly that, at the original identifiers, and records
  the member's decision that the two are distinct so that no later match equates them
  again.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Aggregation
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Dedup
  alias Pluteus.Dedup.Candidate
  alias Pluteus.Ingest
  alias Pluteus.Lifecycle
  alias Pluteus.Matching.MatchRecord
  alias Pluteus.Principals
  alias Pluteus.Repo

  @typedoc "The level an equation is at, which is the decision its pair is decided as."
  @type level :: :same_expression | :same_work

  @doc """
  Equates two expressions or two works found to carry one identifier, answering what was
  done: the equation and what it moved, or why it was not performed.
  """
  @spec equate(Ecto.UUID.t(), Ecto.UUID.t(), level(), map(), MatchRecord.t()) ::
          {:equated, map()} | {:declined, map()} | {:already, map()}
  def equate(one, other, level, identifier, record) do
    [left, right] = Enum.sort([embodiment(one, level), embodiment(other, level)])
    pair = %{"left" => left, "right" => right, "identifier" => identifier}

    case Repo.get_by(Candidate, left_id: left, right_id: right) do
      %Candidate{decision: :distinct} = decided ->
        {:declined, Map.put(pair, "candidate", decided.id)}

      %Candidate{decision: decision} = decided when not is_nil(decision) ->
        {:already, Map.merge(pair, %{"candidate" => decided.id, "decision" => decision})}

      open ->
        candidate = open || raise!(left, right, level, record)
        moving = moving(level, left, right)

        {:ok, _decided} = Dedup.decide(candidate.id, level, Principals.system!().id)

        moved =
          Map.merge(pair, %{
            "candidate" => candidate.id,
            "decision" => Atom.to_string(level),
            "moved" => Map.put(moving, "recycled", recycled(moving))
          })

        report!(record, moved)
        {:equated, moved}
    end
  end

  # The manifestation a pair is made of, for an expression or for a work.
  defp embodiment(expression, :same_expression),
    do: expression |> Catalog.manifestations_of() |> Enum.map(& &1.id) |> Enum.min()

  defp embodiment(work, :same_work) do
    work
    |> Catalog.expressions_of()
    |> Enum.flat_map(&Catalog.manifestations_of(&1.id))
    |> Enum.map(& &1.id)
    |> Enum.min()
  end

  defp raise!(left, right, level, record) do
    %Candidate{}
    |> Candidate.raised_changeset(%{
      left_id: left,
      right_id: right,
      detected_at: DateTime.utc_now(),
      proposed: level,
      source: record.source,
      match_record_id: record.id
    })
    |> Repo.insert!()
  end

  # What the decision is about to move, read before it does: the later manifestation and
  # the expression it leaves, with every aggregate selecting that expression — its
  # arrangement, and whether it selected the survivor too, in which case its selection of
  # the one left goes rather than moving; or the later manifestation's expressions and the
  # works they leave.
  defp moving(:same_expression, left, right) do
    [kept] = Catalog.expressions_in(left)
    [from] = Catalog.expressions_in(right)

    selecting_kept =
      Repo.all(
        from a in Aggregation,
          where: a.aggregated_expression_id == ^kept.id,
          select: a.aggregating_expression_id
      )

    aggregated_by =
      Repo.all(
        from a in Aggregation,
          where: a.aggregated_expression_id == ^from.id,
          select: {a.aggregating_expression_id, a.arrangement}
      )
      |> Enum.map(fn {aggregating, arrangement} ->
        %{
          "aggregating" => aggregating,
          "arrangement" => arrangement,
          "also_selected_kept" => aggregating in selecting_kept
        }
      end)

    %{
      "kept" => kept.id,
      "manifestation" => right,
      "from" => from.id,
      "from_work" => from.work_id,
      "aggregated_by" => aggregated_by
    }
  end

  defp moving(:same_work, left, right) do
    [kept | _] = left |> Catalog.expressions_in() |> Enum.map(& &1.work_id) |> Enum.uniq()

    %{
      "kept" => kept,
      "expressions" =>
        right
        |> Catalog.expressions_in()
        |> Enum.reject(&(&1.work_id == kept))
        |> Map.new(&{&1.id, &1.work_id})
    }
  end

  # The recyclings now holding what the decision emptied.
  defp recycled(%{"from" => from, "from_work" => work}), do: recyclings([from, work])
  defp recycled(%{"expressions" => expressions}), do: recyclings(Map.values(expressions))

  defp recyclings(res_ids) do
    res_ids
    |> Enum.uniq()
    |> Enum.flat_map(fn res_id ->
      case Lifecycle.state(res_id) do
        {:recycled, _res, recycling} -> [recycling.id]
        _not_recycled -> []
      end
    end)
    |> Enum.uniq()
  end

  defp report!(record, moved) do
    # It stands until a person has seen it: no later pass records it again.
    Ingest.record_finding(%{
      stage: :match,
      kind: "equated",
      permanent: true,
      digital_item_id: Repo.get!(Asset, record.asset_id).digital_item_id,
      detail: Map.put(moved, "match_record", record.id)
    })
  end

  @doc """
  Reverses an equation matching performed, from what it recorded as moved: what it
  recycled is restored at its original identifiers, what it moved goes back, and the pair
  is recorded as the member's decision that the two are distinct (spec-05 §8.4, §8.7).
  """
  @spec undo(map(), Ecto.UUID.t()) :: {:ok, Candidate.t()} | {:error, term()}
  def undo(%{"candidate" => candidate_id, "moved" => moved}, principal_id) do
    candidate = Repo.get!(Candidate, candidate_id)

    Repo.transaction(fn ->
      for recycling <- moved["recycled"], do: {:ok, _} = Lifecycle.restore(recycling)
      put_back(moved)

      candidate
      |> Candidate.decision_changeset(%{
        decision: :distinct,
        decided_by: principal_id,
        decided_at: DateTime.utc_now()
      })
      |> Repo.update!()
    end)
  end

  defp put_back(%{"manifestation" => manifestation, "kept" => kept, "from" => from} = moved) do
    {:ok, _} = Catalog.embody(from, manifestation)

    {1, _} =
      Repo.delete_all(
        from e in Embodiment,
          where: e.manifestation_id == ^manifestation and e.expression_id == ^kept
      )

    for selection <- moved["aggregated_by"], do: reselect(selection, kept, from)
  end

  defp put_back(%{"expressions" => expressions}) do
    for {expression, work} <- expressions, do: {:ok, _} = Catalog.realize(work, expression)
  end

  # A selection carried to the survivor goes back to the expression it was of; one dropped
  # because its aggregate selected the survivor already is made again beside that one.
  defp reselect(%{"aggregating" => aggregating, "also_selected_kept" => false}, kept, from) do
    {1, _} =
      Repo.update_all(
        from(a in Aggregation,
          where:
            a.aggregating_expression_id == ^aggregating and a.aggregated_expression_id == ^kept
        ),
        set: [aggregated_expression_id: from]
      )
  end

  defp reselect(
         %{"aggregating" => aggregating, "also_selected_kept" => true} = selection,
         _kept,
         from
       ) do
    {:ok, _} =
      %Aggregation{}
      |> Aggregation.changeset(%{
        aggregating_expression_id: aggregating,
        aggregated_expression_id: from,
        arrangement: selection["arrangement"]
      })
      |> Repo.insert()
  end
end
