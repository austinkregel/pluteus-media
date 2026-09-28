defmodule PluteusWeb.CoreComponentsTest do
  @moduledoc """
  Annex A.9.5's loud variants, and the measurement that decides how a control is built.

  A.9.5 names a failure that produces no error: a class name assembled at run time is
  invisible to the CSS build and generates no rule, so the element renders unstyled
  rather than wrongly styled. The variant set is therefore enumerated and an unmapped
  one raises.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias PluteusWeb.CoreComponents

  describe "A.9.5. A variant set is enumerated and an unmapped one raises" do
    test "every button variant renders, and an unmapped one raises" do
      for variant <- ~w(bare subtle strong solid) do
        assert button(variant) =~ "<button"
      end

      assert_raise KeyError, fn -> button("primary") end
    end

    test "a labelled control is built from the subtle rung and not the solid one" do
      # The measurement behind it: no step of the ramp reaches 4.5:1 against a solid
      # fill's ink in both themes, so a solid fill is a field for a glyph. If `strong`
      # ever gains a solid fill this fails, which is the point.
      assert button("strong") =~ "bg-fill-subtle"
      refute button("strong") =~ "bg-fill-solid"
      assert button("solid") =~ "bg-fill-solid"
    end

    test "a control reaches A.4.2's pointer floor by name" do
      # Written as a number in each component it becomes something each one remembers;
      # asked for by name it is one value the density context can move.
      assert button("subtle") =~ "min-h-target-pointer"
    end
  end

  describe "A.1.4. A template names a role and never a ramp step" do
    test "no component reaches past the semantic tier" do
      # The utilities for the primitives exist, because A.10.1's layer 1 generates them.
      # That they exist is not permission to use them, and this is what enforces it for
      # the components a form is built from.
      rendered = Enum.map_join(~w(bare subtle strong solid), " ", &button/1)

      for step <- ~w(01 02 03 04 05 06 07 08 09 10 11 12) do
        refute rendered =~ "grey-#{step}", "a component reaches base.grey.#{step} directly"
      end
    end
  end

  defp button(variant) do
    assigns = %{variant: variant, __changed__: nil}

    ~H"""
    <CoreComponents.button variant={@variant}>Go</CoreComponents.button>
    """
    |> rendered_to_string()
  end
end
