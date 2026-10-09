defmodule Pluteus.Catalog.Cover do
  @moduledoc """
  The cover a holding is known by.

  spec-04 §4.6 catalogues a cover as a holding of its own, so that ingest does not mistake
  a picture beside an album for a photograph the household keeps. [spec-10] §12.2 then has
  the render boundary present it as a property of what it describes rather than as a
  holding: a cover never appears in a photograph grid, and a release wears it.

  What is answered is the manifestation carrying the cover, not its bytes. A surface asks
  the presentation layer for the size it is drawing at (§11.1), which is what keeps a row
  from fetching a scan at full size and what keeps the stored location off a reachable
  surface (spec-03 §10).
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Catalog.Association
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Refinements
  alias Pluteus.Lifecycle.RecycledRes
  alias Pluteus.Lifecycle.Tombstone
  alias Pluteus.Repo

  @doc """
  The cover each of the given works wears, keyed by work, in one query.

  A work with none is absent rather than present with nothing, so a caller renders what
  it has and says what it has not.
  """
  @spec for_works([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => Ecto.UUID.t()}
  def for_works([]), do: %{}

  def for_works(work_ids) do
    Map.new(
      Repo.all(
        from x in Expression,
          join: b in Embodiment,
          on: b.expression_id == x.id,
          join: link in Association,
          on: link.object_id == b.manifestation_id,
          where: x.work_id in ^work_ids,
          where: link.refinement == ^Refinements.name!("cover-art-of"),
          where: link.subject_id not in subquery(from r in RecycledRes, select: r.res_id),
          where: link.subject_id not in subquery(from t in Tombstone, select: t.res_id),
          select: {x.work_id, link.subject_id}
      )
    )
  end

  @doc """
  The cover one manifestation wears, or the one worn by the work it belongs to.

  A track of a release has no cover of its own and is shown wearing the release's, which
  is what a person means by the picture beside what is playing.
  """
  @spec for_manifestation(Ecto.UUID.t(), Ecto.UUID.t() | nil) :: Ecto.UUID.t() | nil
  def for_manifestation(manifestation_id, grouping_work_id) do
    case own(manifestation_id) do
      nil -> grouping_work_id && for_works([grouping_work_id])[grouping_work_id]
      cover -> cover
    end
  end

  defp own(manifestation_id) do
    Repo.one(
      from link in Association,
        where: link.object_id == ^manifestation_id,
        where: link.refinement == ^Refinements.name!("cover-art-of"),
        where: link.subject_id not in subquery(from r in RecycledRes, select: r.res_id),
        where: link.subject_id not in subquery(from t in Tombstone, select: t.res_id),
        limit: 1,
        select: link.subject_id
    )
  end
end
