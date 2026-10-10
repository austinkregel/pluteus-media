defmodule Pluteus.Catalog.Cover do
  @moduledoc """
  The cover a holding is known by.

  spec-04 §4.6 catalogues a cover as a holding of its own; [spec-10] §12.2 has the render
  boundary present it as a property of what it describes instead.

  Answered as the manifestation carrying it, so a surface asks the presentation layer for
  the size it draws at (§11.1) rather than reaching the stored bytes (spec-03 §10).
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
  The cover each of the given works wears, keyed by work, in one query. A work with none
  is absent rather than present with nothing.
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
  The cover one manifestation wears, or the one worn by the work it belongs to: a track
  has none of its own and wears its release's.
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
