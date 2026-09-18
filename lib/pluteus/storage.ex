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

  @doc """
  The digest of the bytes at a location, as lowercase hex.

  Read in chunks, so a file larger than memory can be checked. A file that
  cannot be opened or read returns the file system's reason: spec-03 §5.2
  records unreadable as an outcome in its own right, distinct from a mismatch.
  """
  @spec digest(String.t(), :crypto.hash_algorithm()) :: {:ok, String.t()} | {:error, term()}
  def digest(location, algorithm) do
    case File.open(path(location), [:read, :binary]) do
      {:ok, device} ->
        result = hash_chunks(device, :crypto.hash_init(algorithm))
        :ok = File.close(device)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp hash_chunks(device, state) do
    case IO.binread(device, 1_048_576) do
      :eof -> {:ok, state |> :crypto.hash_final() |> Base.encode16(case: :lower)}
      {:error, reason} -> {:error, reason}
      chunk -> hash_chunks(device, :crypto.hash_update(state, chunk))
    end
  end

  @doc """
  What an asset records about the bytes at a location: their size and their
  digest, taken now, from the bytes themselves (spec-03 §5.1).
  """
  @spec measure(String.t()) :: {:ok, map()} | {:error, term()}
  def measure(location) do
    with {:ok, %File.Stat{size: size}} <- File.stat(path(location)),
         {:ok, digest} <- digest(location, :sha256) do
      {:ok, %{size: size, digest: digest, digest_algorithm: "sha-256"}}
    end
  end

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
