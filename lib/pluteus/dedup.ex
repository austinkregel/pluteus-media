defmodule Pluteus.Dedup do
  @moduledoc """
  Finds what may be held twice, and records what a person decides about it
  (spec-03 §8).

  Detection produces candidates and nothing else. It never merges, deletes or
  re-points anything, and a pair it has raised before is left exactly as it
  stands, so a person's decision survives every later run.

  A pair is one row whatever raised it, and a decided pair is never raised again
  ([spec-05] §8.5). The index on the pair is what holds that, so a signal added
  later inherits the rule rather than having to honour it.

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
  alias Pluteus.Catalog.Aggregation
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.Association
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Manifestation
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Refinements
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
      for {left_id, right_id, signal} <- found_pairs() do
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
        conflict_target: [:left_id, :right_id]
      )

    count
  end

  # A pair sharing both its bytes and an identifier is found by both queries, and
  # keyed on the pair those two rows collide inside one statement. Taking the
  # first decides which signal is recorded here rather than leaving it to the
  # order the database happens to resolve a conflict in, and digest comes first
  # because bytes are the stronger evidence.
  defp found_pairs do
    Enum.uniq_by(digest_pairs() ++ identifier_pairs(), fn {left_id, right_id, _signal} ->
      {left_id, right_id}
    end)
  end

  @doc """
  Records a pair a member proposes, which no signal found (§8.3).

  The pair is stored in identifier order whichever way round it is given.

  A pair already decided is refused with the decision it carries, because a
  decided pair is settled and re-raising it is how a correction mechanism becomes
  something people turn off ([spec-05] §8.5). A pair a signal has already raised
  and nobody has decided answers with that row: it is the one place the pair
  appears, and a member pointing at it has not failed at anything.
  """
  @spec propose(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) ::
          {:ok, Candidate.t()}
          | {:error,
             Ecto.Changeset.t() | {:already_decided, atom()} | {:not_a_holding, Ecto.UUID.t()}}
  def propose(one_id, other_id, principal_id, now \\ DateTime.utc_now()) do
    [left_id, right_id] = Enum.sort([one_id, other_id])

    with :ok <- a_holding(left_id), :ok <- a_holding(right_id) do
      case raised(left_id, right_id) do
        nil -> record_proposal(left_id, right_id, principal_id, now)
        %Candidate{decision: nil} = open -> {:ok, open}
        %Candidate{decision: decision} -> {:error, {:already_decided, decision}}
      end
    end
  end

  # A pair names two holdings, digital items or manifestations, and every level a
  # decision can name is reached from them. A pair of works, or of anything else, could
  # never be decided, so it is refused here rather than accepted and left to raise when
  # someone tries.
  defp a_holding(res_id) do
    case Repo.get!(Res, res_id) do
      %Res{kind: kind} when kind in [:digital_item, :manifestation] -> :ok
      %Res{} -> {:error, {:not_a_holding, res_id}}
    end
  end

  defp raised(left_id, right_id) do
    Repo.one(from c in Candidate, where: c.left_id == ^left_id and c.right_id == ^right_id)
  end

  defp record_proposal(left_id, right_id, principal_id, now) do
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

  Every level is carried out with the decision, in one transaction. Each moves
  children under the surviving res and recycles whichever of the res they left is
  holding nothing, attributed to the deciding principal. None purges and none
  deletes an asset (§8.3), so every level stays reversible for spec-01 §14.1's
  window. The pair's earlier half — the one whose identifier was minted first —
  is the survivor.

  `:same_holding` names two digital items. The later one's assets are moved under
  the earlier one, and the holding they left is recycled, with its manifestation
  and whatever is above it if they are then holding nothing. The bytes do not
  move.

  `:same_manifestation` is the level above it. The pair names two digital items or
  two manifestations, and the later one's manifestation gives up its digital items
  and its items to the earlier one's, which is then recycled along with any
  expression it was the only manifestation of.

  `:same_expression` is the level above that. The pair names two digital items or
  two manifestations, and the later of the two — the one whose identifier was
  minted second — has its manifestation moved under the earlier one's expression.
  Whichever of the work and expression it was placed under are left holding
  nothing are recycled, so one work remains.

  `:same_work` is the level above it, and is carried out the same way one level
  up: the later one's expressions are realized under the earlier one's work, and
  the work they left is recycled if it is holding nothing. **Both expressions
  remain**, because that is the whole of what this decision says — a live
  recording and a studio recording of one song realize one work and are not one
  realization, and two dumps of one game stand in the same relation (spec-04
  §6.9). A pair that is also one expression is decided `:same_expression`; there
  is no decision that splits an expression back apart.

  `:distinct` carries nothing out. The row is the whole of it, and it is what
  keeps the pair from being raised again (§8.3, [spec-05] §8.5).
  """
  @spec decide(
          Ecto.UUID.t(),
          :same_holding
          | :same_manifestation
          | :same_expression
          | :same_work
          | :place_of_capture
          | :distinct,
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

  defp carry_out(:same_holding, candidate, principal_id, now) do
    case resolve_same_holding(candidate, principal_id, now) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp carry_out(:same_manifestation, candidate, principal_id, now) do
    case resolve_same_manifestation(candidate, principal_id, now) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
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

  # A member accepting where a photograph was taken asserts it: the association is the
  # household's own, and no later answer from a gazetteer replaces it ([spec-05] §8.7).
  # Matching's own coarser answer is what the member has just answered more finely, so it
  # goes; nothing a member wrote is touched.
  defp carry_out(:place_of_capture, candidate, _principal_id, _now) do
    %{place: place, captured: captured} = place_and_captured!(candidate)
    refinement = Refinements.name!("place-of-capture")

    Repo.delete_all(
      from a in Association,
        where: a.subject_id == ^captured and a.refinement == ^refinement,
        where: a.provenance == :automatic
    )

    case Catalog.associate(captured, place, refinement, :local) do
      {:ok, _association} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # The row records it and there is nothing to move. Stated rather than left to a
  # catch-all, so a level added to the vocabulary without a clause here raises
  # instead of recording a decision it did not carry out.
  defp carry_out(:distinct, _candidate, _principal_id, _now), do: :ok

  @doc """
  A member saying a work was not made in a place matching recorded for it ([spec-10]
  §15.1): matching's association is withdrawn, and the pair is recorded as the member's
  decision that the two are distinct, which no later match overturns ([spec-05] §8.7).
  """
  @spec reject_place(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) ::
          {:ok, Candidate.t()} | {:error, term()}
  def reject_place(work_id, place_id, principal_id, now \\ DateTime.utc_now()) do
    refinement = Refinements.name!("place-of-capture")
    [left, right] = Enum.sort([work_id, place_id])

    Repo.transaction(fn ->
      {1, _} =
        Repo.delete_all(
          from a in Association,
            where: a.subject_id == ^work_id and a.object_id == ^place_id,
            where: a.refinement == ^refinement and a.provenance == :automatic
        )

      # A pair already raised — a proposal of this very place from an earlier match — is
      # the one decided; one pair, one row.
      pair =
        Repo.get_by(Candidate, left_id: left, right_id: right) ||
          %Candidate{}
          |> Candidate.proposal_changeset(%{
            left_id: left,
            right_id: right,
            signal: :member,
            detected_at: now,
            raised_by: principal_id
          })
          |> Repo.insert!()

      pair
      |> Candidate.decision_changeset(%{
        decision: :distinct,
        decided_by: principal_id,
        decided_at: now
      })
      |> Repo.update!()
    end)
  end

  @doc """
  Undoes a decision about where a work was made ([spec-10] §15.4), returning what the
  decision replaced.

  An accepted place is withdrawn and the place matching had recorded is restored; a
  proposal declined is open again; a member's rejection of a place matching recorded is
  removed, and that place restored.
  """
  @spec reconsider(Ecto.UUID.t()) :: {:ok, :reopened | :withdrawn} | {:error, term()}
  def reconsider(candidate_id) do
    candidate = Repo.get!(Candidate, candidate_id)
    %{place: place, captured: work} = place_and_captured!(candidate)
    refinement = Refinements.name!("place-of-capture")

    Repo.transaction(fn ->
      case {candidate.signal, candidate.decision} do
        {:matching, :place_of_capture} ->
          {1, _} =
            Repo.delete_all(
              from a in Association,
                where: a.subject_id == ^work and a.object_id == ^place,
                where: a.refinement == ^refinement and a.provenance == :local
            )

          restore_matched(work, candidate.match_record_id, refinement)
          reopen!(candidate)

        {:matching, :distinct} ->
          reopen!(candidate)

        {:member, :distinct} ->
          Repo.delete!(candidate)
          {:ok, _} = Catalog.associate(work, place, refinement, :automatic)
          :withdrawn
      end
    end)
  end

  defp reopen!(candidate) do
    candidate |> Candidate.reopened_changeset() |> Repo.update!()
    :reopened
  end

  # The place the match that raised the proposal recorded, which accepting the proposal
  # withdrew.
  defp restore_matched(work, match_record_id, refinement) do
    case Repo.get!(Pluteus.Matching.MatchRecord, match_record_id).conclusion do
      %{"recorded" => %{"place_id" => recorded}} ->
        {:ok, _} = Catalog.associate(work, recorded, refinement, :automatic)

      %{"recorded" => nil} ->
        :nothing_was_recorded
    end
  end

  # The pair is stored in identifier order, so which one is the place is read from the
  # res rather than from the position.
  defp place_and_captured!(%Candidate{left_id: left, right_id: right}) do
    case {Repo.get!(Res, left).kind, Repo.get!(Res, right).kind} do
      {:place, _other} -> %{place: left, captured: right}
      {_other, :place} -> %{place: right, captured: left}
    end
  end

  defp resolve_same_holding(
         %Candidate{left_id: first_id, right_id: second_id},
         principal_id,
         now
       ) do
    kept = holding_of!(first_id)
    losing = holding_of!(second_id)
    manifestation_id = Repo.get!(DigitalItem, losing).manifestation_id

    for asset <- Catalog.assets_of(losing) do
      {:ok, _} = Catalog.hold(kept, asset.id)
    end

    with :ok <- recycle_each([losing], principal_id, now) do
      recycle_emptied_manifestation(manifestation_id, [losing], principal_id, now)
    end
  end

  defp resolve_same_manifestation(
         %Candidate{left_id: first_id, right_id: second_id},
         principal_id,
         now
       ) do
    kept = manifestation_of!(first_id)
    losing = manifestation_of!(second_id)

    if kept == losing do
      {:error, :already_one_manifestation}
    else
      move_exemplars(losing, kept, principal_id, now)
    end
  end

  # §8.3 moves *children* under the surviving res, and a manifestation's children
  # are its digital items and its items alike. Leaving the items behind would keep
  # the losing manifestation live, so two rows would survive a decision that says
  # they are one.
  defp move_exemplars(losing, kept, principal_id, now) do
    exemplars = Catalog.digital_items_of(losing) ++ Catalog.items_of(losing)

    for exemplar <- exemplars do
      {:ok, _} = Catalog.exemplify(kept, exemplar.id)
    end

    recycle_emptied_manifestation(losing, [], principal_id, now)
  end

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

    emptied = Enum.filter(left, &(Catalog.manifestations_of(&1.id) == []))
    carry_aggregations(emptied, expression_id)
    recycle_emptied(emptied, principal_id, now)
  end

  # An expression the decision empties goes into the bin, and every aggregate that selected
  # it selects the one it was decided to be instead: the compilation a track was placed on
  # still holds that track once it is one expression with the album's. An aggregate that
  # already selects the survivor keeps the one selection it has.
  defp carry_aggregations(emptied, kept_id) do
    for %{id: emptied_id} <- emptied do
      already =
        from a in Aggregation,
          where: a.aggregated_expression_id == ^kept_id,
          select: a.aggregating_expression_id

      {_count, _} =
        Repo.delete_all(
          from a in Aggregation,
            where: a.aggregated_expression_id == ^emptied_id,
            where: a.aggregating_expression_id in subquery(already)
        )

      {_count, _} =
        Repo.update_all(
          from(a in Aggregation, where: a.aggregated_expression_id == ^emptied_id),
          set: [aggregated_expression_id: kept_id]
        )
    end

    :ok
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

  # *same holding* is about the digital item itself, so unlike `manifestation_of!`
  # there is nothing to reach up to. A pair of manifestations decided one holding
  # names a level it does not have, and raising is the answer.
  defp holding_of!(res_id) do
    %Res{kind: :digital_item} = Repo.get!(Res, res_id)
    Repo.get!(DigitalItem, res_id).id
  end

  # Recycling does not delete rows, so a holding just recycled is still returned
  # by `digital_items_of/1`; `going` is what has already gone. On the
  # *same manifestation* path it is empty, because the exemplars moved rather than
  # went.
  defp recycle_emptied_manifestation(manifestation_id, going, principal_id, now) do
    if holds_nothing?(manifestation_id, going) do
      with :ok <- recycle_each([manifestation_id], principal_id, now) do
        manifestation_id
        |> emptied_expressions()
        |> recycle_emptied(principal_id, now)
      end
    else
      :ok
    end
  end

  defp holds_nothing?(manifestation_id, going) do
    holdings = manifestation_id |> Catalog.digital_items_of() |> Enum.map(& &1.id)

    holdings -- going == [] and Catalog.items_of(manifestation_id) == []
  end

  # Embodiments are not deleted here, unlike on the *same expression* path where a
  # manifestation moves: this manifestation is going into the bin, and spec-01
  # §14.3 restores what it held, so removing the link would restore it detached.
  defp emptied_expressions(manifestation_id) do
    manifestation_id
    |> Catalog.expressions_in()
    |> Enum.filter(fn expression ->
      expression.id
      |> Catalog.manifestations_of()
      |> Enum.all?(&(&1.id == manifestation_id))
    end)
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
  #
  # Only a pair a decision can name is raised: two digital items or manifestations,
  # as a member's proposal must be. Two expressions or two works carrying one identifier
  # are equated by matching itself where [spec-05] §8.4 allows it, through a pair of the
  # manifestations embodying them, and a pair of them raised here could never be decided.
  defp identifier_pairs do
    decidable = [:digital_item, :manifestation]

    Repo.all(
      from n in Nomen,
        join: m in Nomen,
        on:
          n.scheme == m.scheme and n.nomen_string == m.nomen_string and
            n.res_id < m.res_id,
        join: a in Res,
        on: a.id == n.res_id,
        join: b in Res,
        on: b.id == m.res_id,
        where: not is_nil(n.scheme),
        where: a.kind in ^decidable and b.kind in ^decidable,
        distinct: true,
        select: {n.res_id, m.res_id, :external_identifier}
    )
  end
end
