defmodule Pluteus.StorageFixtures do
  @moduledoc """
  Real bytes in primary storage, for assets that are measured from them.

  Every file is written under a directory of its own. Tests run concurrently,
  and one that purges an asset removes its bytes; sharing a path would let that
  pull a file out from under another test.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Pluteus.Storage

  @doc """
  A valid one-pixel PNG whose text chunk carries `note`, so that two calls
  with different notes never share a digest.
  """
  @spec png(String.t()) :: binary()
  def png(note) do
    header = <<1::32, 1::32, 8, 2, 0, 0, 0>>
    pixels = :zlib.compress(<<0, 255, 0, 0>>)

    <<0x89, "PNG\r\n", 0x1A, "\n">> <>
      chunk("IHDR", header) <>
      chunk("tEXt", "Comment" <> <<0>> <> note) <>
      chunk("IDAT", pixels) <> chunk("IEND", "")
  end

  @doc """
  Writes bytes under a fresh directory and returns the location, removing
  them when the test exits.
  """
  @spec stored!(String.t(), binary()) :: String.t()
  def stored!(file_name, bytes) do
    location = "t#{System.unique_integer([:positive])}/#{file_name}"
    :ok = Storage.put(location, bytes)
    on_exit(fn -> Storage.delete(location) end)
    location
  end

  defp chunk(type, data) do
    <<byte_size(data)::32>> <> type <> data <> <<:erlang.crc32(type <> data)::32>>
  end
end
