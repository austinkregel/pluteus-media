defmodule Pluteus.Preferences.Registry do
  @moduledoc """
  The preferences a principal holds, and what each may be set to (spec-10 §20).

  §20 requires a registry be populated before the section depending on it is built
  and forbids a code path supplying a value a registry omits, so a key's domain and
  its default are read from here rather than written anywhere in code. A key the file
  does not carry raises.

  Three domains are expressible. `one_of` names its values; `number` bounds a quantity
  and names its unit; `language_range` admits one language range, or the value it
  reserves for narrowing nothing. Every value is stored and answered as text, because
  one column holds them all and a quantity's unit is the registry's to state rather than
  the column's to imply.

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
  The value a key's domain reserves to mean that it narrows nothing.

  A key whose domain reserves none raises, rather than answering a value that would
  then stand for something the domain never said.
  """
  @spec reserved(String.t()) :: String.t()
  def reserved(key), do: key |> domain() |> Map.fetch!("reserved")

  @doc """
  What a request naming this preference with no value asks for.

  A key that states none raises.
  """
  @spec empty_request(String.t()) :: String.t()
  def empty_request(key), do: key |> entry() |> Map.fetch!("empty_request")

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
      %{"kind" => "language_range", "reserved" => reserved} -> range?(reserved, value)
    end
  end

  # [RFC4647] §2.1's basic language range, less the wildcard. The grammar admits any run
  # of letters, so the reserved value is spelled as a range would be and is matched ahead
  # of it.
  #
  # The wildcard `*` is refused: [spec-10] §6.1 matches it against every tag, so its
  # second clause makes the tagged names the only candidates and drops the household's own
  # untagged vocabulary, which spec-01 §7.4 forbids standing for the absence of a
  # preference.
  @range ~r/^[A-Za-z]{1,8}(-[A-Za-z0-9]{1,8})*$/

  defp range?(reserved, reserved), do: true
  defp range?(_reserved, value), do: Regex.match?(@range, value)

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
