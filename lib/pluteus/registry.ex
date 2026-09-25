defmodule Pluteus.Registry do
  @moduledoc """
  Reads a seed vocabulary from `priv/registries` (spec-01 §7.5).

  A file is read once and held for the life of the node. Its contents are
  generic, identical across every deployment, and replaced by a release.

  Callers reach a value through an accessor that names what it is for, so a
  value a file omits raises where it is needed rather than resolving to nil:
  spec-10 §20 forbids a code path supplying a value a registry omits.
  """

  @doc """
  The decoded contents of `priv/registries/<name>.json`.
  """
  @spec read(String.t()) :: map()
  def read(name) do
    key = {__MODULE__, name}

    case :persistent_term.get(key, nil) do
      nil ->
        loaded =
          :pluteus
          |> :code.priv_dir()
          |> Path.join("registries/#{name}.json")
          |> File.read!()
          |> Jason.decode!()

        :persistent_term.put(key, loaded)
        loaded

      loaded ->
        loaded
    end
  end
end
