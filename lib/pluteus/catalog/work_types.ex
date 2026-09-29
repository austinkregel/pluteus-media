defmodule Pluteus.Catalog.WorkTypes do
  @moduledoc """
  Which attributes are significant per category of work (spec-01 §6.5, §17).

  LRM §5.6 requires the implementation to say which they are, and §6.5 carries the table.
  They measure distance from the canonical form and do nothing else: they order competing
  expressions of one work (§8.6), and where a work has one expression in one manifestation
  §6.5's automatic promotion applies and they never discriminate.

  A work's type is its own categorization scheme. [ANNEX-A] §A.9 reads LRM §4.2.3 as
  permitting several independent schemes on one entity, so this is not a re-reading of the
  category placement records — `of_category/1` maps one onto the other as a default, which
  spec-04 §6.2 leaves a member free to correct.

  Three types correspond to no category placement produces and are reached only by that
  correction. §6.5 authored personal record for a relative's letters, which no ingest path
  yields.
  """

  alias Pluteus.Registry

  @source "work_types"

  @doc """
  The categorization scheme a work's type is recorded under.
  """
  @spec scheme() :: String.t()
  def scheme, do: "https://pluteus.invalid/schemes/work-type"

  @doc """
  Every type of work the registry names.
  """
  @spec all() :: [String.t()]
  def all, do: registry() |> Map.fetch!("work_types") |> Map.keys() |> Enum.sort()

  @doc """
  The attributes that are significant for a type of work.

  A type the registry does not name raises, rather than ordering expressions by an empty
  set and calling the result a distance.
  """
  @spec attributes(String.t()) :: [String.t()]
  def attributes(type) do
    registry() |> Map.fetch!("work_types") |> Map.fetch!(type) |> Map.fetch!("attributes")
  end

  @doc """
  Where a type's attributes come from: LRM, or authored here.
  """
  @spec source(String.t()) :: String.t()
  def source(type) do
    registry() |> Map.fetch!("work_types") |> Map.fetch!(type) |> Map.fetch!("source")
  end

  @doc """
  The type of work a category of work belongs to.

  A category the registry does not map raises. Placement records a category from evidence
  or from the broad class (spec-04 §6.3), so a category reaching this without a type is a
  registry that has fallen behind the one placement draws from.
  """
  @spec of_category(String.t()) :: String.t()
  def of_category(category), do: registry() |> Map.fetch!("of_category") |> Map.fetch!(category)

  @doc """
  Every category of work the registry maps.
  """
  @spec categories() :: [String.t()]
  def categories, do: registry() |> Map.fetch!("of_category") |> Map.keys() |> Enum.sort()

  defp registry, do: Registry.read(@source)
end
