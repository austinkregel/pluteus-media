defmodule Pluteus.Preferences do
  @moduledoc """
  What a principal has chosen about how things are shown to them (spec-10 §14.5).

  Every function here takes the principal whose preferences they are, and there is
  none that answers another's. §14.5 puts these with consumption data rather than
  with the catalog — "they disclose a disability as directly as a play history
  discloses a taste" — and §21 states they "are not household-visible", so the
  absence of a function that reads across principals is the guarantee rather than a
  check inside one.

  A principal who has set nothing is answered the registry's defaults, so a caller
  never distinguishes unset from default and no surface has to carry a fallback of
  its own. `forget/2` returns a preference to its default by removing the row, which
  is why setting a value to its default and forgetting it are the same state.
  """

  import Ecto.Query

  alias Pluteus.Preferences.Preference
  alias Pluteus.Preferences.Registry
  alias Pluteus.Repo

  @doc """
  Every preference a principal holds, keyed as the registry names them.

  Each key carries the principal's value where they have set one and the registry's
  default where they have not.
  """
  @spec held_by(Ecto.UUID.t()) :: %{String.t() => String.t()}
  def held_by(principal_id) do
    set =
      Preference
      |> where([p], p.principal_id == ^principal_id)
      |> select([p], {p.key, p.value})
      |> Repo.all()
      |> Map.new()

    Map.merge(Registry.defaults(), set)
  end

  @doc """
  One preference a principal holds, or its default.
  """
  @spec held(Ecto.UUID.t(), String.t()) :: String.t()
  def held(principal_id, key) do
    case Repo.get_by(Preference, principal_id: principal_id, key: key) do
      nil -> Registry.default(key)
      %Preference{value: value} -> value
    end
  end

  @doc """
  Sets one preference, replacing whatever the principal held under that key.
  """
  @spec set(Ecto.UUID.t(), String.t(), String.t()) ::
          {:ok, Preference.t()} | {:error, Ecto.Changeset.t()}
  def set(principal_id, key, value) do
    %Preference{}
    |> Preference.changeset(%{principal_id: principal_id, key: key, value: value})
    |> Repo.insert(
      on_conflict: {:replace, [:value, :updated_at]},
      conflict_target: [:principal_id, :key]
    )
  end

  @doc """
  Sets several preferences, or none of them.

  All or nothing because a client sends a set and a partial write would leave a
  person looking at half of what they asked for with nothing saying which half.
  """
  @spec set_many(Ecto.UUID.t(), %{String.t() => String.t()}) ::
          {:ok, %{String.t() => String.t()}} | {:error, String.t(), Ecto.Changeset.t()}
  def set_many(principal_id, values) do
    values
    |> Enum.reduce(Ecto.Multi.new(), fn {key, value}, multi ->
      Ecto.Multi.insert(multi, key, changeset(principal_id, key, value),
        on_conflict: {:replace, [:value, :updated_at]},
        conflict_target: [:principal_id, :key]
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _written} -> {:ok, held_by(principal_id)}
      {:error, key, changeset, _done} -> {:error, key, changeset}
    end
  end

  @doc """
  Returns a preference to its default by removing the row that overrode it.
  """
  @spec forget(Ecto.UUID.t(), String.t()) :: :ok
  def forget(principal_id, key) do
    Preference
    |> where([p], p.principal_id == ^principal_id and p.key == ^key)
    |> Repo.delete_all()

    :ok
  end

  defp changeset(principal_id, key, value) do
    Preference.changeset(%Preference{}, %{principal_id: principal_id, key: key, value: value})
  end
end
