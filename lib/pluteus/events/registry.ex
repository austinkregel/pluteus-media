defmodule Pluteus.Events.Registry do
  @moduledoc """
  The event type vocabulary, which spec-01 §11.3 makes seed data and §17
  registers.

  §11.2 puts every event in exactly one class: a **consumption** event records
  what a person played, read or viewed and is visible to that principal alone; a
  **platform** event records what happened to the holdings and is visible to the
  household. §11.3's table is the minimum each class distinguishes, and this is
  where a deployment's own additions to either are named.

  The class is not stored beside a type, because the two classes are two tables:
  `Pluteus.Events` holds the consumption class and scopes every read by principal,
  and `Pluteus.PlatformEvents` holds the platform class and scopes none. Asking
  which class a type belongs to is therefore asking which table records it.
  """

  alias Pluteus.Registry

  @source "events"

  @doc """
  Every type in a class, which is `:consumption` or `:platform`.
  """
  @spec types(:consumption | :platform) :: [String.t()]
  def types(class) when class in [:consumption, :platform] do
    registry() |> Map.fetch!(to_string(class)) |> Enum.map(&Map.fetch!(&1, "name"))
  end

  @doc """
  Whether a type belongs to a class.

  A class outside the two raises, because §11.2 admits no third.
  """
  @spec in_class?(String.t(), :consumption | :platform) :: boolean()
  def in_class?(type, class), do: type in types(class)

  defp registry, do: Registry.read(@source)
end
