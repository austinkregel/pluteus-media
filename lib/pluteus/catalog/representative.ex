defmodule Pluteus.Catalog.Representative do
  @moduledoc """
  spec-01 §6.5's representative expression attributes: recording them, and the promotion
  LRM §5.6 grounds.

  A work's type decides which attributes are significant, and the type comes from the
  work's category through `Pluteus.Catalog.WorkTypes`. A work carrying no category has no
  type, so it has no attribute set and none may be recorded against it — which is the state
  a work has before placement categorizes it.

  **The promotion.** §6.5 permits promoting an expression's attributes to the work's where
  the work has a single expression in a single manifestation, and [ANNEX-A] §A.9 quotes LRM
  §5.6 grounding it in "the vast majority of cases where new works are realized through a
  single expression". That is the household's own media, and where it applies the ordering
  never has to discriminate.

  The condition is checked and not assumed. A container carrying several audio languages is
  placed as several expressions of one work, so the promotion does not apply to it, and the
  selection §8.6 describes is what chooses among them.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Work
  alias Pluteus.Catalog.WorkTypes
  alias Pluteus.Ingest.Place
  alias Pluteus.Repo

  @doc """
  The type of work a work is, from the category it carries.

  Nil where it carries none, which is a work placement has not categorized rather than one
  whose type is unknowable.
  """
  @spec type_of(Ecto.UUID.t()) :: String.t() | nil
  def type_of(work_id) do
    case Catalog.category_of(work_id, Place.category_scheme()) do
      nil -> nil
      category -> WorkTypes.of_category(category)
    end
  end

  @doc """
  The attributes significant for a work, or none where it carries no category.
  """
  @spec significant(Ecto.UUID.t()) :: [String.t()]
  def significant(work_id) do
    case type_of(work_id) do
      nil -> []
      type -> WorkTypes.attributes(type)
    end
  end

  @doc """
  Records what an expression's §6.5 attributes are.

  Refused where a key is not significant for the work the expression realizes, and where the
  work carries no category at all: nothing is significant then, so nothing may be recorded.
  """
  @spec describe(Ecto.UUID.t(), map()) :: {:ok, Expression.t()} | {:error, Ecto.Changeset.t()}
  def describe(expression_id, attributes) do
    expression = Repo.get!(Expression, expression_id)

    expression
    |> Expression.attributes_changeset(
      %{significant_attributes: attributes},
      significant(expression.work_id)
    )
    |> Repo.update()
  end

  @doc """
  Records what a work's representative attributes are.
  """
  @spec represent(Ecto.UUID.t(), map()) :: {:ok, Work.t()} | {:error, Ecto.Changeset.t()}
  def represent(work_id, attributes) do
    Work
    |> Repo.get!(work_id)
    |> Work.attributes_changeset(%{representative_attributes: attributes}, significant(work_id))
    |> Repo.update()
  end

  @doc """
  A person's revision of a work's or an expression's attributes: those named are set,
  the rest are kept, and a nil value removes the one it names.

  Merged rather than replaced, because a member recording what kind of recording
  something is has said nothing about its key, and a write that replaced the map would
  erase whatever was already known about it.
  """
  @spec revise(:work | :expression, Ecto.UUID.t(), map()) ::
          {:ok, Work.t() | Expression.t()} | {:error, Ecto.Changeset.t()}
  def revise(:work, work_id, changes) do
    represent(work_id, merged(Repo.get!(Work, work_id).representative_attributes, changes))
  end

  def revise(:expression, expression_id, changes) do
    expression = Repo.get!(Expression, expression_id)

    describe(expression_id, merged(expression.significant_attributes, changes))
  end

  defp merged(held, changes) do
    Enum.reduce(changes, held, fn
      {attribute, nil}, held -> Map.delete(held, attribute)
      {attribute, value}, held -> Map.put(held, attribute, value)
    end)
  end

  @doc """
  Promotes an expression's attributes to its work's, where §6.5's condition holds.

  Answers `:promoted` where it did, and why not where it did not, so a caller that expected
  the promotion can say which part of the condition failed rather than finding an empty map
  later.
  """
  @spec promote(Ecto.UUID.t()) ::
          :promoted
          | {:not_promoted, :several_expressions | :several_manifestations | :nothing_to_promote}
  def promote(work_id) do
    case Repo.all(from e in Expression, where: e.work_id == ^work_id) do
      [%Expression{significant_attributes: attributes} = expression] ->
        promote_one(work_id, expression, attributes)

      _several_or_none ->
        {:not_promoted, :several_expressions}
    end
  end

  defp promote_one(_work_id, _expression, attributes) when map_size(attributes) == 0,
    do: {:not_promoted, :nothing_to_promote}

  defp promote_one(work_id, expression, attributes) do
    if embodiments(expression.id) == 1 do
      {:ok, _work} = represent(work_id, attributes)
      :promoted
    else
      {:not_promoted, :several_manifestations}
    end
  end

  defp embodiments(expression_id) do
    Repo.aggregate(from(e in Embodiment, where: e.expression_id == ^expression_id), :count)
  end
end
