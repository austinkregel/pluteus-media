defmodule Pluteus.Dedup do
  @moduledoc """
  Finds what may be held twice, and records what a person decides about it
  (spec-03 §8).

  Detection produces candidates and nothing else. It never merges, deletes or
  re-points anything, and a pair it has raised before is left exactly as it
  stands, so a person's decision survives every later run.

  Byte identity is not duplication. The acquired original and its backup copy
  are byte-identical by design, so two assets sharing a digest are a candidate
  only when they realize different digital items.

  Two of §8.2's three signals are detected: a shared digest and a shared
  external identifier. Perceptual hashing is not, since nothing here computes
  one; the signal is accepted so that candidates from it can be recorded once
  something does. A member may propose a pair no signal found, as two scans of
  one letter, which differ in every byte, require.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Manifestation
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Res
  alias Pluteus.Dedup.Candidate
  alias Pluteus.Lifecycle
  alias Pluteus.Repo

  @doc """
  Records every candidate pair not already recorded, and returns how many were
  new.
  """
  @spec detect(DateTime.t()) :: non_neg_integer()
  def detect(now \\ DateTime.utc_now()) do
    rows =
      for {left_id, right_id, signal} <- digest_pairs() ++ identifier_pairs() do
        %{
          id: UUIDv7.generate(),
          left_id: left_id,
          right_id: right_id,
          signal: signal,
          detected_at: now,
          inserted_at: now,
          updated_at: now
        }
      end

    {count, _} =
      Repo.insert_all(Candidate, rows,
        on_conflict: :nothing,
        conflict_target: [:left_id, :right_id, :signal]
      )

    count
  end

  @doc """
  Records a pair a member proposes, which no signal found (§8.3).

  The pair is stored in identifier order whichever way round it is given.
  """
  @spec propose(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) ::
          {:ok, Candidate.t()} | {:error, Ecto.Changeset.t()}
  def propose(one_id, other_id, principal_id, now \\ DateTime.utc_now()) do
    [left_id, right_id] = Enum.sort([one_id, other_id])

    %Candidate{}
    |> Candidate.proposal_changeset(%{
      left_id: left_id,
      right_id: right_id,
      signal: :member,
      detected_at: now,
      raised_by: principal_id
    })
    |> Repo.insert()
  end

  @doc """
  Records a person's decision about one pair.

  `:same_holding` records that the two are one holding; bringing them under one
  manifestation is a catalog operation performed separately, and never the
  deletion of an asset (§8.3).

  `:same_expression` is carried out with the decision, in one transaction. The
  pair names two digital items or two manifestations, and the later of the two
  — the one whose identifier was minted second — has its manifestation moved
  under the earlier one's expression. Whichever of the work and expression it
  was placed under are left holding nothing are recycled, attributed to the
  deciding principal, so one work remains.

  `:same_work` is the level above it, and is carried out the same way one level
  up: the later one's expressions are realized under the earlier one's work, and
  the work they left is recycled if it is holding nothing. **Both expressions
  remain**, because that is the whole of what this decision says — a live
  recording and a studio recording of one song realize one work and are not one
  realization, and two dumps of one game stand in the same relation (spec-04
  §6.9). A pair that is also one expression is decided `:same_expression`; there
  is no decision that splits an expression back apart.
  """
  @spec decide(
          Ecto.UUID.t(),
          :same_holding | :same_expression | :same_work | :distinct,
          Ecto.UUID.t(),
          DateTime.t()
        ) :: {:ok, Candidate.t()} | {:error, term()}
  def decide(candidate_id, decision, principal_id, now \\ DateTime.utc_now()) do
    candidate = Repo.get!(Candidate, candidate_id)

    Repo.transaction(fn ->
      decided = record_decision(candidate, decision, principal_id, now)
      carry_out(decision, candidate, principal_id, now)
      decided
    end)
  end

  defp record_decision(candidate, decision, principal_id, now) do
    candidate
    |> Candidate.decision_changeset(%{
      decision: decision,
      decided_by: principal_id,
      decided_at: now
    })
    |> Repo.update()
    |> case do
      {:ok, decided} -> decided
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp carry_out(:same_expression, candidate, principal_id, now) do
    case resolve_same_expression(candidate, principal_id, now) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp carry_out(:same_work, candidate, principal_id, now) do
    case resolve_same_work(candidate, principal_id, now) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp carry_out(_decision, _candidate, _principal_id, _now), do: :ok

  defp resolve_same_expression(
         %Candidate{left_id: first_id, right_id: second_id},
         principal_id,
         now
       ) do
    first = manifestation_of!(first_id)
    second = manifestation_of!(second_id)

    case Catalog.expressions_in(first) do
      [kept] -> move_under(second, kept.id, principal_id, now)
      [] -> {:error, :first_embodies_no_expression}
      [_ | _] -> {:error, :first_embodies_several_expressions}
    end
  end

  defp resolve_same_work(
         %Candidate{left_id: first_id, right_id: second_id},
         principal_id,
         now
       ) do
    first = manifestation_of!(first_id)
    second = manifestation_of!(second_id)

    case works_realized_by(first) do
      [kept] -> realize_under(kept, Catalog.expressions_in(second), principal_id, now)
      [] -> {:error, :first_embodies_no_expression}
      [_ | _] -> {:error, :first_realizes_several_works}
    end
  end

  defp works_realized_by(manifestation_id) do
    manifestation_id
    |> Catalog.expressions_in()
    |> Enum.map(& &1.work_id)
    |> Enum.uniq()
  end

  # Every expression the pair's later half embodies is realized under the surviving
  # work. The expressions themselves are untouched: §8.3's *same work* says the two
  # realize one creation and says nothing about the realizations being one.
  defp realize_under(work_id, expressions, principal_id, now) do
    moving = Enum.reject(expressions, &(&1.work_id == work_id))

    for expression <- moving do
      {:ok, _} = Catalog.realize(work_id, expression.id)
    end

    moving
    |> Enum.map(& &1.work_id)
    |> Enum.uniq()
    |> Enum.filter(&(Catalog.expressions_of(&1) == []))
    |> recycle_each(principal_id, now)
  end

  defp recycle_each(res_ids, principal_id, now) do
    Enum.reduce_while(res_ids, :ok, fn res_id, :ok ->
      case Lifecycle.recycle(res_id, principal_id, now: now) do
        {:ok, _recycling} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {res_id, reason}}}
      end
    end)
  end

  defp move_under(manifestation_id, expression_id, principal_id, now) do
    left = Catalog.expressions_in(manifestation_id) |> Enum.reject(&(&1.id == expression_id))

    {:ok, _} = Catalog.embody(expression_id, manifestation_id)

    {_count, _} =
      Repo.delete_all(
        from e in Embodiment,
          where: e.manifestation_id == ^manifestation_id,
          where: e.expression_id in ^Enum.map(left, & &1.id)
      )

    left
    |> Enum.filter(&(Catalog.manifestations_of(&1.id) == []))
    |> recycle_emptied(principal_id, now)
  end

  # An expression left with no manifestation goes; its work goes with it when
  # it was the work's only expression, and recycling the work takes the
  # expression along.
  defp recycle_emptied(expressions, principal_id, now) do
    work_ids = expressions |> Enum.map(& &1.work_id) |> Enum.uniq()

    expression_counts =
      Map.new(
        Repo.all(
          from e in Expression,
            where: e.work_id in ^work_ids,
            group_by: e.work_id,
            select: {e.work_id, count(e.id)}
        )
      )

    expressions
    |> Enum.map(fn expression ->
      if expression_counts[expression.work_id] == 1, do: expression.work_id, else: expression.id
    end)
    |> Enum.uniq()
    |> recycle_each(principal_id, now)
  end

  defp manifestation_of!(res_id) do
    case Repo.get!(Res, res_id) do
      %Res{kind: :manifestation} -> Repo.get!(Manifestation, res_id).id
      %Res{kind: :digital_item} -> Repo.get!(DigitalItem, res_id).manifestation_id
    end
  end

  @doc """
  Every pair still waiting for a decision.
  """
  @spec open() :: [Candidate.t()]
  def open, do: Repo.all(from c in Candidate, where: is_nil(c.decision))

  @spec involving(Ecto.UUID.t()) :: [Candidate.t()]
  def involving(res_id) do
    Repo.all(from c in Candidate, where: c.left_id == ^res_id or c.right_id == ^res_id)
  end

  defp digest_pairs do
    Repo.all(
      from a in Asset,
        join: b in Asset,
        on: a.digest == b.digest and a.digital_item_id < b.digital_item_id,
        distinct: true,
        select: {a.digital_item_id, b.digital_item_id, :digest}
    )
  end

  # A name in a scheme is an identifier (spec-01 §4.3), and §4.3 tolerates two
  # things carrying the same one, which is what makes it a candidate and not a
  # fact.
  defp identifier_pairs do
    Repo.all(
      from n in Nomen,
        join: m in Nomen,
        on:
          n.scheme == m.scheme and n.nomen_string == m.nomen_string and
            n.res_id < m.res_id,
        where: not is_nil(n.scheme),
        distinct: true,
        select: {n.res_id, m.res_id, :external_identifier}
    )
  end
end
