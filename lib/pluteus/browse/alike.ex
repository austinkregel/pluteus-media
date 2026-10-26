defmodule Pluteus.Browse.Alike do
  @moduledoc """
  What tells apart results that resolve to one name ([spec-10] §6.2's second slot,
  criterion 14).

  LRM asks that homonymy be avoided, and where the catalog holds a homonym the interface
  resolves it: two holdings shown as "Pride and Prejudice" beside each other are a
  question the list has to answer. The parenthetical is the first fact the catalog
  records that differs between every one of them — what kind of thing each is, what it
  is held as, when it was made, who it is by — because that is the fact a person would
  reach for to say which they meant.

  Where nothing recorded tells them apart the parenthetical says so. Inventing a
  difference, or numbering them by position, would be a disambiguator that disambiguates
  nothing, and two holdings nothing tells apart are what spec-03's duplicate decisions
  exist for.

  The names compared are those of the results a surface lists, which are the ones a
  person has in front of them to confuse.
  """

  alias Pluteus.Representation.ComposedName

  @typedoc """
  What a surface already knows about each result, keyed by result.
  """
  @type facts :: %{
          names: %{Ecto.UUID.t() => String.t()},
          categories: %{Ecto.UUID.t() => String.t()},
          formats: %{Ecto.UUID.t() => String.t()},
          dates: %{Ecto.UUID.t() => String.t()},
          credited: %{Ecto.UUID.t() => [String.t()]}
        }

  @doc """
  The parenthetical each result sharing its name with another carries, keyed by result.
  A result whose name is its own carries none and is absent.
  """
  @spec among([Ecto.UUID.t()], facts()) :: %{Ecto.UUID.t() => String.t()}
  def among(results, facts) do
    results
    |> Enum.group_by(&Map.fetch!(facts.names, &1))
    |> Enum.flat_map(fn
      {_name, [_alone]} -> []
      {_name, alike} -> told_apart(alike, facts)
    end)
    |> Map.new()
  end

  # The first fact every one of them carries and no two share.
  defp told_apart(alike, facts) do
    stated =
      Enum.find_value(differences(facts), fn said ->
        values = Enum.map(alike, said)

        if Enum.all?(values) and length(Enum.uniq(values)) == length(alike),
          do: Enum.zip(alike, values)
      end)

    stated || Enum.map(alike, &{&1, "nothing recorded tells these #{length(alike)} apart"})
  end

  # In the order a person would reach for them.
  defp differences(facts) do
    [
      &kind(facts.categories[&1]),
      &facts.formats[&1],
      &facts.dates[&1],
      &credited(facts.credited[&1])
    ]
  end

  defp kind(category), do: ComposedName.category_noun(category)

  defp credited(nil), do: nil
  defp credited([]), do: nil
  defp credited(names), do: Enum.join(names, ", ")
end
