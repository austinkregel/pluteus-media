defmodule Pluteus.Storage do
  @moduledoc """
  Primary storage: the directory asset bytes are written under.

  An asset's `location` is a path relative to the configured root. Where the
  root is and how it is laid out is spec-04's concern; this module guarantees
  only that a location cannot name anything outside it.
  """

  @spec root() :: Path.t()
  def root do
    :pluteus
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.fetch!(:root)
  end

  @doc """
  The absolute path a location names.

  Raises for a location that would escape the root. A `..` segment in a
  location is not a storage layout, it is a request for a file this system
  does not own.
  """
  @spec path(String.t()) :: Path.t()
  def path(location) do
    case location |> String.trim_leading("/") |> Path.safe_relative() do
      {:ok, relative} -> Path.join(root(), relative)
      :error -> raise ArgumentError, "location escapes primary storage: #{inspect(location)}"
    end
  end

  @spec put(String.t(), iodata()) :: :ok
  def put(location, bytes) do
    target = path(location)
    File.mkdir_p!(Path.dirname(target))
    File.write!(target, bytes)
  end

  @spec read(String.t()) :: binary()
  def read(location), do: location |> path() |> File.read!()

  @spec exists?(String.t()) :: boolean()
  def exists?(location), do: location |> path() |> File.exists?()

  @doc """
  Removes the bytes at a location.

  Returns the file system's answer rather than raising, because a caller
  removing several may need to report every one that failed rather than stop
  at the first.
  """
  @spec delete(String.t()) :: :ok | {:error, File.posix()}
  def delete(location), do: location |> path() |> File.rm()
end
