defmodule Pluteus.Places do
  @moduledoc """
  Where a work was made, as the catalog records it (spec-01 §6.3's place of capture), and
  the finer places proposed for it and not yet decided (spec-05 §8.5, §9.7).

  A place is read with the places containing it, outward, so a region is said with its
  country and a locality with its region and country: the place recorded is what the
  evidence supported, and the containing places say where that is without claiming
  anything finer ([spec-10] §5.3).

  Each place of capture carries the layer it was written in, which is whether a tool or a
  person put it there ([spec-10] §15.3).
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Catalog.Association
  alias Pluteus.Catalog.Refinements
  alias Pluteus.Catalog.Res
  alias Pluteus.Dedup.Candidate
  alias Pluteus.Repo

  @typedoc "A place a work was made in: the place, the places containing it, and its layer."
  @type captured :: %{
          place_id: Ecto.UUID.t(),
          within: [Ecto.UUID.t()],
          provenance: :seeded | :automatic | :local
        }

  @typedoc "A finer place proposed for a work, and the candidate a person decides it by."
  @type proposed :: %{candidate_id: Ecto.UUID.t(), place_id: Ecto.UUID.t()}

  @doc """
  Every place of capture recorded for a work, a person's first.
  """
  @spec captured(Ecto.UUID.t()) :: [captured()]
  def captured(work_id) do
    refinement = Refinements.name!("place-of-capture")

    Repo.all(
      from a in Association,
        where: a.subject_id == ^work_id and a.refinement == ^refinement,
        select: {a.object_id, a.provenance}
    )
    |> Enum.sort_by(fn {_place, provenance} -> provenance != :local end)
    |> Enum.map(fn {place, provenance} ->
      %{place_id: place, within: within(place, [place]), provenance: provenance}
    end)
  end

  @doc """
  The places proposed as where a work was made, whose candidates nobody has decided.
  """
  @spec proposed(Ecto.UUID.t()) :: [proposed()]
  def proposed(work_id) do
    Repo.all(
      from c in Candidate,
        where: c.proposed == :place_of_capture and is_nil(c.decision),
        where: c.left_id == ^work_id or c.right_id == ^work_id,
        order_by: c.detected_at,
        select: {c.id, c.left_id, c.right_id}
    )
    |> Enum.map(fn {id, left, right} ->
      %{candidate_id: id, place_id: if(left == work_id, do: right, else: left)}
    end)
  end

  @typedoc "A person's decision about where a work was made, which they may undo."
  @type decided :: %{
          candidate_id: Ecto.UUID.t(),
          place_id: Ecto.UUID.t(),
          decision: :place_of_capture | :distinct
        }

  @doc """
  Every decision a person has made about a place for a work: a proposal taken or
  declined, and a place matching recorded that a person said it was not made in.
  """
  @spec decided(Ecto.UUID.t()) :: [decided()]
  def decided(work_id) do
    Repo.all(
      from c in Candidate,
        join: other in Res,
        on: (other.id == c.left_id or other.id == c.right_id) and other.id != ^work_id,
        where: c.left_id == ^work_id or c.right_id == ^work_id,
        where: other.kind == :place and not is_nil(c.decision),
        order_by: c.decided_at,
        select: {c.id, other.id, c.decision}
    )
    |> Enum.map(fn {id, place, decision} ->
      %{candidate_id: id, place_id: place, decision: decision}
    end)
  end

  # The containing places, nearest first. A place recorded as within one it contains is a
  # catalog that cannot be read, and raises rather than being read as far as it goes.
  defp within(place, met) do
    refinement = Refinements.name!("place-within-place")

    case Repo.all(
           from a in Association,
             where: a.subject_id == ^place and a.refinement == ^refinement,
             order_by: a.object_id,
             limit: 1,
             select: a.object_id
         ) do
      [] ->
        []

      [containing] ->
        if containing in met do
          raise "place #{containing} is recorded as containing itself, through #{inspect(met)}"
        end

        [containing | within(containing, [containing | met])]
    end
  end
end
