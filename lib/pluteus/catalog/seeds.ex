defmodule Pluteus.Catalog.Seeds do
  @moduledoc """
  Loads shipped catalog data from JSON files.

  Identifiers are read from the files, never minted. Two deployments of the same
  release therefore hold the same identifier for the same concept, which is what
  lets an upgrade recognise a row it shipped previously rather than inserting a
  second one alongside it (spec-01 §4.2).

  A seed entry missing an identifier is an authoring error and raises. Filling
  one in would produce a row that looks seeded but differs between installs, and
  nothing downstream could tell the difference.

  `replace/1` is what an upgrade runs. It removes every name marked as shipped
  and writes the release's own, leaving res rows in place so that names the
  household attached to them are not carried off by a foreign key.
  """

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Res
  alias Pluteus.Repo

  @nomen_fields ~w(
    id
    nomen_string
    scheme
    language
    script
    context_of_use
    reference_source
    intended_audience
    script_conversion
  )

  defmodule Error do
    @moduledoc """
    Raised when a seed file cannot be loaded as written.
    """
    defexception [:message]
  end

  @doc """
  Loads every `.json` file in the application's `priv/seeds` directory.
  """
  @spec load() :: :ok
  def load, do: load(default_dir())

  @doc """
  Loads every `.json` file in `dir`, in filename order.
  """
  @spec load(Path.t()) :: :ok
  def load(dir), do: load_dir(dir, :insert)

  @doc """
  Replaces the shipped set with the one in `dir`.

  Every name the household wrote survives, as does every correction it made to a
  shipped name: §7.5 records corrections as separate local rows precisely so
  that this operation can be wholesale.
  """
  @spec replace(Path.t()) :: :ok
  def replace(dir) do
    entries = read(dir)

    entries
    |> Enum.flat_map(fn entry -> Enum.map(Map.get(entry, "nomens", []), & &1["id"]) end)
    |> Catalog.delete_seeded_nomens_except()

    Enum.each(entries, &apply_entry(&1, :upsert))
  end

  @spec default_dir() :: Path.t()
  def default_dir, do: Application.app_dir(:pluteus, "priv/seeds")

  defp load_dir(dir, mode) do
    dir
    |> read()
    |> Enum.each(&apply_entry(&1, mode))
  end

  # Every file is parsed before anything is written, so that a replacement knows
  # the full set of identifiers the release ships before deciding what to drop.
  defp read(dir) do
    unless File.dir?(dir) do
      raise Error, message: "seed directory does not exist: #{dir}"
    end

    dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(fn path ->
      path
      |> File.read!()
      |> Jason.decode!()
      |> Enum.map(&validate_entry(&1, path))
    end)
  end

  defp validate_entry(%{"id" => _, "kind" => kind} = entry, path) do
    nomens = Map.get(entry, "nomens", [])

    if nomens == [] and String.to_existing_atom(kind) not in Res.unnamed_kinds() do
      raise Error,
        message: "seed entry of kind #{kind} carries no nomen, which §6.1 requires, in #{path}"
    end

    Enum.each(nomens, &validate_nomen(&1, path))
    entry
  end

  defp validate_entry(entry, path) do
    raise Error, message: "seed entry needs an id and a kind, got #{inspect(entry)} in #{path}"
  end

  defp validate_nomen(%{"id" => _, "nomen_string" => _} = nomen, path) do
    unknown = Map.keys(nomen) -- @nomen_fields

    unless unknown == [] do
      raise Error, message: "nomen has unknown fields #{inspect(unknown)} in #{path}"
    end
  end

  defp validate_nomen(nomen, path) do
    raise Error,
      message: "seed nomen needs an id and a nomen_string, got #{inspect(nomen)} in #{path}"
  end

  # One transaction per entry. §6.1 requires a res of a named kind to carry a
  # nomen at commit, and an entry's names are written after its res.
  defp apply_entry(%{"id" => id, "kind" => kind} = entry, mode) do
    attrs = %{id: id, kind: String.to_existing_atom(kind)}

    {:ok, :written} =
      Repo.transaction(fn ->
        {:ok, res} =
          case mode do
            :insert -> Catalog.create_res(attrs)
            :upsert -> Catalog.upsert_res(attrs)
          end

        entry
        |> Map.get("nomens", [])
        |> Enum.each(&write_nomen(&1, res.id, mode))

        :written
      end)
  end

  defp write_nomen(nomen, res_id, mode) do
    attrs =
      nomen
      |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
      |> Map.put(:res_id, res_id)
      |> Map.put(:provenance, :seeded)

    {:ok, _nomen} =
      case mode do
        :insert -> Catalog.create_nomen(attrs)
        :upsert -> Catalog.upsert_nomen(attrs)
      end
  end
end
