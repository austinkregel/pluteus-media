defmodule Pluteus.Catalog.Distance do
  @moduledoc """
  How far an expression stands from the canonical form of its work (spec-01 §6.5).

  §6.5 says the expression-level values of a work's representative attributes "give a
  measure of distance from the canonical form" and leaves the measure to the deployment.
  This one counts disagreements: each attribute significant for the work's type contributes
  one where the two values differ and nothing where they match.

  One rule serves every attribute, whatever its values are — a float, a string, a boolean —
  so an attribute the registry gains later needs no comparison of its own. What it gives up
  is nearness: an aspect ratio of 1.78 is as far from 1.85 as from 2.35, because a rule that
  measured the gap would have to be written per attribute type and could say nothing at all
  about a key or a language.

  **An attribute only one level carries contributes nothing.** A work with no recorded
  aspect ratio does not disagree with an expression that has one; it says nothing about it.
  Counting that as a difference would let an absence stand for a negation.

  The ordering is separated from any query because §7.4 requires resolution be
  deterministic, and determinism is a property of the ordering rather than of the rows
  arriving in a particular order.
  """

  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Work

  @doc """
  How many of a work's significant attributes an expression differs from it on.

  `significant` is the attribute set the work's type names, which the caller reads from the
  registry: an attribute either level carries and the type does not name is not part of the
  measure, because the ordering is over what the type makes significant.
  """
  @spec of(Work.t(), Expression.t(), [String.t()]) :: non_neg_integer()
  def of(%Work{} = work, %Expression{} = expression, significant) do
    Enum.count(significant, &differs?(work, expression, &1))
  end

  defp differs?(work, expression, attribute) do
    case {Map.fetch(work.representative_attributes, attribute),
          Map.fetch(expression.significant_attributes, attribute)} do
      {{:ok, canonical}, {:ok, value}} -> canonical != value
      _one_level_or_neither -> false
    end
  end

  @doc """
  A work's expressions, nearest the canonical form first.

  Ties break on the identifier, which is time-ordered (§4.1) and cannot itself tie, so the
  ordering is total and the same expressions always come back in the same order — which is
  what §7.4 requires of anything resolution rests on.

  A work carrying no representative attributes puts every expression at distance zero, so
  the order is by identifier alone. That is the shape §6.5's automatic promotion leaves
  where it did not apply, and it is an honest ordering rather than an arbitrary one: nothing
  is known that would separate them.
  """
  @spec order([Expression.t()], Work.t(), [String.t()]) :: [Expression.t()]
  def order(expressions, %Work{} = work, significant) do
    Enum.sort_by(expressions, &{of(work, &1, significant), &1.id})
  end
end
