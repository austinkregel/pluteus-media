defmodule Pluteus.Preferences.Registry do
  @moduledoc """
  The preferences a principal holds, and what each may be set to (spec-10 §20).

  §20 requires a registry be populated before the section depending on it is built
  and forbids a code path supplying a value a registry omits, so a key's domain and
  its default are read from here rather than written anywhere in code. A key the file
  does not carry raises.

  Two domains are expressible. `one_of` names its values; `number` bounds a quantity
  and names its unit. Every value is stored and answered as text, because one column
  holds them all and a quantity's unit is the registry's to state rather than the
  column's to imply.

  The caption properties are this deployment's own. spec-10 §17.4 requires caption
  presentation "be adjustable by the person, persisted per principal" and names no
  property of it, and §20 makes a registry where a section's values are populated.
  """

  alias Pluteus.Registry

  @doc """
  Every key a principal may hold a preference under.
  """
  @spec keys() :: [String.t()]
  def keys, do: registry() |> Map.fetch!("keys") |> Map.keys() |> Enum.sort()

  @doc """
  One key's domain, as the registry states it.
  """
  @spec domain(String.t()) :: map()
  def domain(key), do: key |> entry() |> Map.fetch!("domain")

  @doc """
  The value a key takes where a principal has set none.
  """
  @spec default(String.t()) :: String.t()
  def default(key), do: key |> entry() |> Map.fetch!("default")

  @doc """
  Every key with its default, which is what a principal holding nothing is answered.
  """
  @spec defaults() :: %{String.t() => String.t()}
  def defaults, do: Map.new(keys(), &{&1, default(&1)})

  @doc """
  Whether a value is inside a key's domain.

  A key the registry does not carry raises rather than answering false: a caller
  asking about an unknown key has a bug, and a false would hide it as a refusal.
  """
  @spec admits?(String.t(), String.t()) :: boolean()
  def admits?(key, value) when is_binary(value) do
    case domain(key) do
      %{"kind" => "one_of", "values" => values} -> value in values
      %{"kind" => "number"} = bounds -> within?(bounds, value)
    end
  end

  defp within?(%{"minimum" => low, "maximum" => high}, value) do
    case Float.parse(value) do
      {number, ""} -> number >= low and number <= high
      _not_a_number -> false
    end
  end

  defp entry(key) do
    registry()
    |> Map.fetch!("keys")
    |> Map.fetch!(key)
  end

  defp registry, do: Registry.read("preferences")
end
