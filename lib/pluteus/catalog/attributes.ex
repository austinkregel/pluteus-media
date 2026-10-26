defmodule Pluteus.Catalog.Attributes do
  @moduledoc """
  The rule both levels of spec-01 §6.5's attributes are held to.

  A work's representative attributes and an expression's values of the same attributes are
  keyed alike, and both are bounded by what the work's type names. The check is here rather
  than twice, because two copies of one rule are two chances for them to differ.
  """

  import Ecto.Changeset

  alias Pluteus.Catalog.WorkTypes

  @doc """
  Refuses a map carrying a key the work's type does not name, or a value outside the
  vocabulary of an attribute whose values are a closed set.

  The offending keys and values are named in the message. An attribute outside the set
  would be stored and then ignored by an ordering that reads only the type's own, and a
  value outside a vocabulary would be a distance from the canonical form that no other
  recording could ever be measured as sharing.
  """
  @spec only(Ecto.Changeset.t(), atom(), [String.t()]) :: Ecto.Changeset.t()
  def only(changeset, field, permitted) do
    case get_change(changeset, field) do
      nil ->
        changeset

      attributes ->
        changeset
        |> refuse_unnamed(field, attributes, permitted)
        |> refuse_unknown_values(field, attributes)
    end
  end

  defp refuse_unknown_values(changeset, field, attributes) do
    outside =
      for {attribute, value} <- Enum.sort(attributes),
          vocabulary = WorkTypes.vocabulary(attribute),
          vocabulary != nil and value not in vocabulary,
          do: {attribute, value, vocabulary}

    Enum.reduce(outside, changeset, fn {attribute, value, vocabulary}, changeset ->
      add_error(
        changeset,
        field,
        "gives #{attribute} the value #{inspect(value)}, which is not one of " <>
          Enum.join(vocabulary, ", ")
      )
    end)
  end

  defp refuse_unnamed(changeset, field, attributes, permitted) do
    case attributes |> Map.keys() |> Enum.reject(&(&1 in permitted)) |> Enum.sort() do
      [] ->
        changeset

      unnamed ->
        add_error(
          changeset,
          field,
          "names #{Enum.join(unnamed, ", ")}, which this work's type does not"
        )
    end
  end
end
