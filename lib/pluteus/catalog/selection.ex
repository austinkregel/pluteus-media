defmodule Pluteus.Catalog.Selection do
  @moduledoc """
  Which of a work's expressions a principal is given (spec-01 §8.6, [spec-10] §8.1).

  §8.1 requires the primary action resolve to a specific expression without asking, and
  §8.6 says how: "Selection therefore returns the preferred expression where available and
  the default otherwise." Three things answer, in that order.

  **What the principal chose.** §8.1's ask-once answer, where one was recorded and the
  expression it names still realizes the work.

  **What the principal prefers.** Their `audio_language` range, matched against the
  expression's own resolved name by [RFC4647] basic filtering — the same matching §6.1's
  language step uses. Placement names each parallel expression of a container by the
  language of its audio, so the language of the expression is in its nomen rather than among
  §6.5's attributes: a moving image's significant attributes are aspect ratio and
  colourization, and every expression of one container shares both.

  **What the work is.** `Pluteus.Catalog.Distance`'s ordering, nearest the canonical form
  first, which §8.6 prefers to container track order "so that 'original audio' derives from
  what the work is rather than from how the file was muxed". Ties break on the identifier,
  so the answer is the same across calls as §7.4 requires.

  A work with no live expression raises. §8.6's promise that selection is never empty rests
  on the container's default track always being present, which is a fact about a container
  and not about a work that has lost its expressions.
  """

  import Ecto.Changeset, only: [add_error: 3]
  import Ecto.Query, only: [from: 2]

  alias Pluteus.Catalog.Distance
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.ExpressionChoice
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Representative
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Catalog.Work
  alias Pluteus.Preferences
  alias Pluteus.Preferences.Registry
  alias Pluteus.Repo

  @doc """
  The expression a principal is given for a work, and how many others there were.

  The count is §8.1's: the alternatives "MUST be reachable in one action from the same place,
  and that action MUST state how many there are".
  """
  @spec for_principal(Ecto.UUID.t(), Ecto.UUID.t(), Profile.t()) ::
          {Expression.t(), non_neg_integer()}
  def for_principal(work_id, principal_id, %Profile{} = profile) do
    case Repo.all(from e in Expression, where: e.work_id == ^work_id) do
      [] ->
        raise ArgumentError, "work #{work_id} has no expression to select among"

      [only] ->
        {only, 0}

      expressions ->
        {decide(work_id, principal_id, profile, expressions), length(expressions) - 1}
    end
  end

  @doc """
  Records the answer §8.1 asks for, replacing whatever this principal had chosen.

  Refused where the expression does not realize the work: a choice naming one that does not
  is a choice the selection would discard on reading it.
  """
  @spec choose(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, ExpressionChoice.t()} | {:error, Ecto.Changeset.t()}
  def choose(principal_id, work_id, expression_id) do
    %ExpressionChoice{}
    |> ExpressionChoice.changeset(%{
      principal_id: principal_id,
      work_id: work_id,
      expression_id: expression_id
    })
    |> realizes(work_id, expression_id)
    |> Repo.insert(
      on_conflict: {:replace, [:expression_id, :updated_at]},
      conflict_target: [:principal_id, :work_id]
    )
  end

  @doc """
  What this principal chose for this work, or nil.
  """
  @spec chosen(Ecto.UUID.t(), Ecto.UUID.t()) :: Ecto.UUID.t() | nil
  def chosen(principal_id, work_id) do
    Repo.one(
      from c in ExpressionChoice,
        where: c.principal_id == ^principal_id and c.work_id == ^work_id,
        select: c.expression_id
    )
  end

  defp realizes(changeset, work_id, expression_id) do
    query = from e in Expression, where: e.id == ^expression_id and e.work_id == ^work_id

    if Repo.exists?(query),
      do: changeset,
      else: add_error(changeset, :expression_id, "does not realize that work")
  end

  defp decide(work_id, principal_id, profile, expressions) do
    standing = Enum.find(expressions, &(&1.id == chosen(principal_id, work_id)))

    standing || preferred(principal_id, profile, expressions) || nearest(work_id, expressions)
  end

  # §8.6's preferred expression. The value the domain reserves narrows nothing, so a principal
  # who has stated no language falls through to what the work is.
  defp preferred(principal_id, profile, expressions) do
    range = Preferences.held(principal_id, "audio_language")

    if range == Registry.reserved("audio_language"),
      do: nil,
      else: matching(range, profile, expressions)
  end

  defp matching(range, profile, expressions) do
    names = Resolution.resolve_many(Enum.map(expressions, & &1.id), profile)

    Enum.find(expressions, fn expression ->
      Resolution.matches?(names[expression.id] && names[expression.id].language, range)
    end)
  end

  defp nearest(work_id, expressions) do
    work = Repo.get!(Work, work_id)

    expressions
    |> Distance.order(work, Representative.significant(work_id))
    |> hd()
  end
end
