defmodule Pluteus.Matching.Registry do
  @moduledoc """
  spec-05 §15's registries: the external identifier schemes, the corpora the deployment
  holds, and the order of evidence rank it applies.

  **This is the one list of external identifier schemes.** A nomen carrying an identifier
  is written in one of these, and `Pluteus.Surfaces.Registry.nomen_schemes/0` reads them
  from here rather than keeping a list of its own, so a scheme cannot be known to one and
  not the other.

  A scheme names the level it identifies (§4.1), because a match at one level licenses
  conclusions about the levels above it and none about those below (§4.3), and a scheme
  without a level would be an identifier nobody could act on.
  """

  alias Pluteus.Registry

  @source "matching"

  @doc """
  Every external identifier scheme the registry names.
  """
  @spec schemes() :: [String.t()]
  def schemes, do: "schemes" |> fetch() |> Map.delete("for") |> Map.keys() |> Enum.sort()

  @doc """
  A scheme's name, where the registry holds it, so a writer names a scheme the registry
  vouches for. One it does not hold raises, rather than writing an identifier in a scheme
  nothing can act on.
  """
  @spec scheme!(String.t()) :: String.t()
  def scheme!(name) do
    _entry = scheme(name)
    name
  end

  @doc """
  The entity level a scheme identifies (§4.1).
  """
  @spec level(String.t()) :: String.t()
  def level(scheme), do: scheme |> scheme() |> Map.fetch!("level")

  @doc """
  Whether one res may carry several identifiers of a scheme at one level (§5.4).
  """
  @spec several?(String.t()) :: boolean()
  def several?(scheme), do: scheme |> scheme() |> Map.fetch!("several")

  @doc """
  The check-digit algorithm a scheme's identifiers carry (§4.4), or nil where it has none.
  """
  @spec check(String.t()) :: String.t() | nil
  def check(scheme), do: scheme |> scheme() |> Map.get("check")

  @doc """
  The levels a scheme may identify.
  """
  @spec levels() :: [String.t()]
  def levels, do: "levels" |> fetch() |> Map.fetch!("known")

  @doc """
  Every corpus the deployment holds.
  """
  @spec corpora() :: [String.t()]
  def corpora, do: "corpora" |> fetch() |> Map.delete("for") |> Map.keys() |> Enum.sort()

  @doc """
  The schemes a corpus answers.
  """
  @spec answers(String.t()) :: [String.t()]
  def answers(corpus), do: corpus |> corpus() |> Map.fetch!("answers")

  @doc """
  How a corpus reaches the household (§5.7): fetched, replicated or dropped.
  """
  @spec acquisition(String.t()) :: :fetched | :replicated | :dropped
  def acquisition(corpus) do
    case corpus |> corpus() |> Map.fetch!("acquisition") do
      "fetched" -> :fetched
      "replicated" -> :replicated
      "dropped" -> :dropped
    end
  end

  @doc """
  Whether a corpus's snapshot can advance (§5.6).
  """
  @spec advances?(String.t()) :: boolean()
  def advances?(corpus), do: corpus |> corpus() |> Map.fetch!("advances")

  @doc """
  The terms a corpus's data is published under, as the registry states them.
  """
  @spec terms(String.t()) :: String.t()
  def terms(corpus), do: corpus |> corpus() |> Map.fetch!("terms")

  @doc """
  The order of evidence rank the deployment applies (§5.3).
  """
  @spec rank_order() :: [String.t()]
  def rank_order, do: "rank_order" |> fetch() |> Map.fetch!("order")

  defp scheme(scheme), do: "schemes" |> fetch() |> Map.fetch!(scheme)
  defp corpus(corpus), do: "corpora" |> fetch() |> Map.fetch!(corpus)

  defp fetch(key), do: @source |> Registry.read() |> Map.fetch!(key)
end
