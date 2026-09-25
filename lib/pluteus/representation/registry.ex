defmodule Pluteus.Representation.Registry do
  @moduledoc """
  The field names an absence assertion may be about (spec-10 §20), which spec-02
  §6.5 requires be drawn from a registry.

  An annotation whose subject is a named field says that the field holds no value
  and why: that a photographer was sought and not found, that a date will not be
  recovered, that a letter positively has no second page. Without the field name
  the assertion has no subject — "not found" about a photograph says nothing.

  **A field this registry does not name cannot carry one of those three
  assertions**, and its absence is reported as *not yet examined*, which is true.
  The vocabulary is what stops the mechanism becoming a free-text store of claims
  about arbitrary keys.

  A field carrying a `derived` source names the tool whose derivation establishes
  *not yet examined* and whose finding establishes *attempted, failed*.
  """

  alias Pluteus.Registry

  @source "fields"

  @doc """
  Every field an absence assertion may be about.
  """
  @spec absence_fields() :: [map()]
  def absence_fields, do: Map.fetch!(registry(), "absence_fields")

  @doc """
  Whether a name is in the vocabulary at all.
  """
  @spec named?(String.t()) :: boolean()
  def named?(name), do: Enum.any?(absence_fields(), &(&1["name"] == name))

  @doc """
  The res kinds a field may be asserted about.

  A name outside the vocabulary raises: a caller asking which kinds an unnamed
  field applies to has already lost the argument.
  """
  @spec kinds_of(String.t()) :: [String.t()]
  def kinds_of(name) do
    case Enum.find(absence_fields(), &(&1["name"] == name)) do
      nil -> raise KeyError, "#{name} is not a field an absence assertion may be about"
      field -> Map.fetch!(field, "kinds")
    end
  end

  @doc """
  Whether a field may be asserted about a res of this kind.
  """
  @spec about?(String.t(), atom() | String.t()) :: boolean()
  def about?(name, kind), do: named?(name) and to_string(kind) in kinds_of(name)

  @doc """
  The fields of a kind whose value and whose failure come from a deriving tool.

  These are what a representation iterates to report a derived measurement's
  state, and what maps a finding's tool back to the field it was about.
  """
  @spec derived_fields(atom() | String.t()) :: [map()]
  def derived_fields(kind) do
    kind = to_string(kind)

    Enum.filter(absence_fields(), fn field ->
      Map.has_key?(field, "derived") and kind in Map.fetch!(field, "kinds")
    end)
  end

  defp registry, do: Registry.read(@source)
end
