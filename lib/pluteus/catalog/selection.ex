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

  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Distance
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.ExpressionChoice
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Representative
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Catalog.Work
  alias Pluteus.Preferences
  alias Pluteus.Preferences.Registry
  alias Pluteus.Repo

  @typedoc """
  What a principal is given for a work.

  `by` says which of the three answered, which is what §8.6:794 needs: where the resolved
  expression is not what the principal's preference asked for, the surface indicates it
  unobtrusively, and it can only do that if it is told.

  `digital_item` is the file the action would act on, and is nil for a work the household
  describes but holds no file for (spec-01 §5.2). There is nothing to act on then, and
  §8.1's action cannot exist however well the expression resolved.
  """
  @type t :: %{
          expression: Expression.t(),
          digital_item: Ecto.UUID.t() | nil,
          alternatives: non_neg_integer(),
          by: :only | :chosen | :preferred | :nearest
        }

  @doc """
  The expression and digital item a principal is given for a work, and how many other
  expressions there were.

  The count is §8.1's: the alternatives "MUST be reachable in one action from the same place,
  and that action MUST state how many there are".
  """
  @spec for_principal(Ecto.UUID.t(), Ecto.UUID.t(), Profile.t()) :: t()
  def for_principal(work_id, principal_id, %Profile{} = profile) do
    case Repo.all(from e in Expression, where: e.work_id == ^work_id) do
      [] ->
        raise ArgumentError, "work #{work_id} has no expression to select among"

      [only] ->
        answer(only, :only, 0)

      expressions ->
        {expression, by} = decide(work_id, principal_id, profile, expressions)

        answer(expression, by, length(expressions) - 1)
    end
  end

  defp answer(expression, by, alternatives) do
    %{
      expression: expression,
      digital_item: carrier(expression.id),
      alternatives: alternatives,
      by: by
    }
  end

  # The file the action would act on. Ordered by identifier so a holding carrying several
  # files resolves to the same one across calls, which §7.4 requires of what a surface shows.
  defp carrier(expression_id) do
    Repo.one(
      from d in DigitalItem,
        join: b in Embodiment,
        on: b.manifestation_id == d.manifestation_id,
        where: b.expression_id == ^expression_id,
        order_by: d.id,
        limit: 1,
        select: d.id
    )
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

    cond do
      standing -> {standing, :chosen}
      wanted = preferred(principal_id, profile, expressions) -> {wanted, :preferred}
      true -> {nearest(work_id, expressions), :nearest}
    end
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
