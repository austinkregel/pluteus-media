defmodule Pluteus.Catalog.DistanceTest do
  @moduledoc """
  spec-01 §6.5's measure of distance from the canonical form.

  Pure, so every case is a struct rather than a row: the ordering's determinism is a
  property of the function and §7.4 rests on it, so it is asserted where nothing else can
  influence the answer.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Catalog.Distance
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Work

  @significant ~w(aspect_ratio colourization)

  defp work(attributes), do: %Work{id: "01a0-work", representative_attributes: attributes}

  defp expression(id, attributes),
    do: %Expression{id: id, significant_attributes: attributes}

  describe "the measure counts disagreements" do
    test "matching every attribute is no distance at all" do
      canonical = %{"aspect_ratio" => 1.78, "colourization" => "colour"}

      assert Distance.of(work(canonical), expression("a", canonical), @significant) == 0
    end

    test "each attribute that differs contributes one" do
      canonical = %{"aspect_ratio" => 1.78, "colourization" => "colour"}

      one = expression("a", %{"aspect_ratio" => 1.33, "colourization" => "colour"})
      two = expression("b", %{"aspect_ratio" => 1.33, "colourization" => "monochrome"})

      assert Distance.of(work(canonical), one, @significant) == 1
      assert Distance.of(work(canonical), two, @significant) == 2
    end

    test "nearness is not measured, only difference" do
      # A rule that measured the gap would have to be written per attribute type and could
      # say nothing about a key or a language, so 1.85 and 2.35 are equally far from 1.78.
      canonical = work(%{"aspect_ratio" => 1.78})

      near = expression("a", %{"aspect_ratio" => 1.85})
      far = expression("b", %{"aspect_ratio" => 2.35})

      assert Distance.of(canonical, near, @significant) ==
               Distance.of(canonical, far, @significant)
    end

    test "an attribute the type does not name is not part of the measure" do
      canonical = work(%{"aspect_ratio" => 1.78, "key" => "D minor"})
      differing = expression("a", %{"aspect_ratio" => 1.78, "key" => "C major"})

      assert Distance.of(canonical, differing, @significant) == 0
    end
  end

  describe "an attribute only one level carries" do
    test "a work that records nothing disagrees with nothing" do
      assert Distance.of(work(%{}), expression("a", %{"aspect_ratio" => 1.78}), @significant) == 0
    end

    test "an expression that records nothing disagrees with nothing" do
      assert Distance.of(work(%{"aspect_ratio" => 1.78}), expression("a", %{}), @significant) == 0
    end

    test "a described expression is no further than an undescribed one that matches" do
      # Counting an absence as a difference would let it stand for a negation.
      canonical = work(%{"aspect_ratio" => 1.78, "colourization" => "colour"})

      whole = expression("a", %{"aspect_ratio" => 1.78, "colourization" => "colour"})
      partial = expression("b", %{"aspect_ratio" => 1.78})

      assert Distance.of(canonical, whole, @significant) ==
               Distance.of(canonical, partial, @significant)
    end
  end

  describe "the ordering is total" do
    test "nearest the canonical form comes first" do
      canonical = work(%{"aspect_ratio" => 1.78, "colourization" => "colour"})

      far = expression("c", %{"aspect_ratio" => 1.33, "colourization" => "monochrome"})
      near = expression("b", %{"aspect_ratio" => 1.78, "colourization" => "colour"})
      middle = expression("a", %{"aspect_ratio" => 1.33, "colourization" => "colour"})

      assert Distance.order([far, near, middle], canonical, @significant) == [near, middle, far]
    end

    test "a tie breaks on the identifier, so the same set always answers alike" do
      canonical = work(%{"aspect_ratio" => 1.78})

      first = expression("01a0-a", %{"aspect_ratio" => 1.33})
      second = expression("01a0-b", %{"aspect_ratio" => 1.33})

      for arrival <- [[first, second], [second, first]] do
        assert Distance.order(arrival, canonical, @significant) == [first, second]
      end
    end

    test "a work carrying nothing orders by identifier alone" do
      # The shape §6.5's promotion leaves where it did not apply. Nothing is known that
      # would separate them, so the order says nothing beyond being stable.
      first = expression("01a0-a", %{"aspect_ratio" => 2.35})
      second = expression("01a0-b", %{"aspect_ratio" => 1.33})

      assert Distance.order([second, first], work(%{}), @significant) == [first, second]
    end
  end
end
