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
  something does.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Dedup.Candidate
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
  Records a person's decision about one pair.

  `:same_holding` records that the two are one holding; bringing them under one
  manifestation is a catalog operation performed separately, and never the
  deletion of an asset (§8.3).
  """
  @spec decide(Ecto.UUID.t(), :same_holding | :distinct, Ecto.UUID.t(), DateTime.t()) ::
          {:ok, Candidate.t()} | {:error, Ecto.Changeset.t()}
  def decide(candidate_id, decision, principal_id, now \\ DateTime.utc_now()) do
    Candidate
    |> Repo.get!(candidate_id)
    |> Candidate.decision_changeset(%{
      decision: decision,
      decided_by: principal_id,
      decided_at: now
    })
    |> Repo.update()
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
