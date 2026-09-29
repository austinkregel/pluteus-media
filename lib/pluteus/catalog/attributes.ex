defmodule Pluteus.Catalog.Attributes do
  @moduledoc """
  The rule both levels of spec-01 §6.5's attributes are held to.

  A work's representative attributes and an expression's values of the same attributes are
  keyed alike, and both are bounded by what the work's type names. The check is here rather
  than twice, because two copies of one rule are two chances for them to differ.
  """

  import Ecto.Changeset

  @doc """
  Refuses a map carrying a key the work's type does not name.

  The offending keys are named in the message. An attribute outside the set would be stored
  and then ignored by an ordering that reads only the type's own, which is a value the
  catalog holds and nothing can act on.
  """
  @spec only(Ecto.Changeset.t(), atom(), [String.t()]) :: Ecto.Changeset.t()
  def only(changeset, field, permitted) do
    case get_change(changeset, field) do
      nil -> changeset
      attributes -> refuse_unnamed(changeset, field, attributes, permitted)
    end
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
