defmodule Pluteus.Catalog.Refinements do
  @moduledoc """
  The association refinements this release ships (spec-01 §6.3, §17).

  LRM-R33 (a res to a place) and LRM-R35 (a res to a time-span) are declared at res
  level and are many-to-many, and both scope notes expect an implementation to refine
  them into specific types. §6.3 makes that a MUST and fixes what the registry carries:
  the refinements a document in this series cites, and no others. LRM names further
  candidates — time of work conception, period of ownership of an item, date of birth of
  a person — and none is carried, because a refinement nothing writes is a row that only
  looks like coverage.

  §17 makes these seed data rather than specification, so a release adds one and no
  deployment is asked to invent it.

  ## A relation written untyped stays untyped

  §6.3 is explicit that a relation written before its refinement existed cannot be
  classified afterwards: nothing recorded which kind it would have been. So the cost of
  an unregistered refinement is not a row to fix later but a row whose meaning is gone,
  which is why `Pluteus.Catalog.associate/3` refuses a name this registry does not hold
  rather than writing it and leaving the question open.
  """

  alias Pluteus.Registry

  @doc """
  Every refinement name a release may write.
  """
  @spec names() :: [String.t()]
  def names, do: Enum.map(all(), & &1["name"])

  @doc """
  Every refinement, with the relation it refines and the document that cites it.
  """
  @spec all() :: [map()]
  def all, do: Registry.read("refinements") |> Map.fetch!("refinements")

  @doc """
  The relation a refinement refines.

  Raises where the name is not one this release ships, which is the same refusal
  `associate/3` makes and for the same reason.
  """
  @spec relation(String.t()) :: String.t()
  def relation(name) do
    case Enum.find(all(), &(&1["name"] == name)) do
      %{"relation" => relation} -> relation
      nil -> raise ArgumentError, unknown(name)
    end
  end

  @doc """
  Whether this release ships a refinement by that name.
  """
  @spec known?(String.t()) :: boolean()
  def known?(name), do: name in names()

  @doc """
  A refinement's own name, asserting this release ships it.

  What a caller naming one refinement wants: the string, and a loud failure where the
  registry no longer carries it, rather than a string nothing writes.
  """
  @spec name!(String.t()) :: String.t()
  def name!(name) do
    if known?(name), do: name, else: raise(ArgumentError, unknown(name))
  end

  @doc """
  The message a refusal carries, which names what was asked for and what exists.
  """
  @spec unknown(String.t()) :: String.t()
  def unknown(name) do
    "#{inspect(name)} is not an association refinement this release ships. " <>
      "A relation recorded without one cannot be classified afterwards, so nothing " <>
      "is written. The names are: #{Enum.join(names(), ", ")}."
  end

  @doc """
  Every refinement of one relation.
  """
  @spec of_relation(String.t()) :: [String.t()]
  def of_relation(relation) do
    for %{"name" => name, "relation" => ^relation} <- all(), do: name
  end
end
