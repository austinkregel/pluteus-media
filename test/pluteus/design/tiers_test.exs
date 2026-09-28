defmodule Pluteus.Design.TiersTest do
  @moduledoc """
  A.1.4's lint: "Only `sys` tokens may be referenced from templates, component code or
  component styles, enforced by the lint rule A.1.5 requires."

  A primitive generates utilities of its own, so a template naming one renders exactly
  as intended. A.1.4 admits only `sys`, and a match has to sit inside a quoted string
  to count.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Design.Tokens

  @sources ["lib/pluteus_web/**/*.{ex,heex}", "assets/css/app.css"]

  describe "A.1.4. Only sys is referenced outside the token layer" do
    test "no template or component names a primitive" do
      for {file, line, class} <- findings(primitive_classes()) do
        flunk("#{file}:#{line} names the primitive `#{class}`; A.1.4 admits only sys")
      end
    end

    test "no template or component names a primitive's variable" do
      variables = ~w(--color-grey- --color-hue- --color-ink- --color-signal- var(--base-)

      for {file, line, class} <- findings(variables) do
        flunk("#{file}:#{line} reaches #{class} directly; A.1.4 admits only sys")
      end
    end

    test "the search finds the sources it is meant to" do
      assert Enum.count_until(sources(), 6) == 6
      assert Enum.any?(sources(), &String.ends_with?(&1, "app.css"))
      assert Enum.any?(sources(), &String.ends_with?(&1, ".heex"))
    end

    test "a primitive written in a class is caught and a role is not" do
      assert [_ | _] = offences(~s(<div class="bg-grey-03">), primitive_classes())
      assert [] = offences(~s(<div class="bg-surface-raised">), primitive_classes())
    end
  end

  # Each primitive under every utility prefix Tailwind generates it for.
  defp primitive_classes do
    names =
      Tokens.all()
      |> Map.keys()
      |> Enum.filter(&String.starts_with?(&1, "base."))
      |> Enum.map(fn path -> path |> String.split(".") |> Enum.drop(1) |> Enum.join("-") end)

    for prefix <- ~w(bg text border fill stroke ring decoration accent divide outline),
        name <- names do
      "#{prefix}-#{name}"
    end
  end

  defp sources do
    Enum.flat_map(@sources, fn pattern -> Path.wildcard(Path.join(File.cwd!(), pattern)) end)
  end

  defp findings(needles) do
    for path <- sources(),
        {line, number} <- Enum.with_index(String.split(File.read!(path), "\n"), 1),
        needle <- offences(line, needles) do
      {Path.relative_to(path, File.cwd!()), number, needle}
    end
  end

  # A class attribute and a `var()` reference both sit inside a quoted string.
  defp offences(line, needles) do
    quoted = Regex.scan(~r/"([^"]*)"/, line, capture: :all_but_first) |> List.flatten()

    for needle <- needles, Enum.any?(quoted, &String.contains?(&1, needle)), do: needle
  end
end
