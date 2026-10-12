defmodule Pluteus.Ingest.Probe do
  @moduledoc """
  Reads a container's streams, codecs, dispositions, chapters and tags with
  `ffprobe` (spec-04 §5.1).

  This parses arbitrary bytes from the inbox in a child process of the
  application. spec-04 §11 records what that exposes.
  """

  alias Pluteus.Storage

  @doc """
  The probe output for the bytes at a location, or ffprobe's own account of why
  it could not read them.
  """
  @spec probe(String.t()) :: {:ok, map()} | {:error, {:ffprobe, non_neg_integer(), String.t()}}
  def probe(location), do: location |> Storage.path() |> probe_file()

  @doc """
  Probes a file that is not at a location, which is how a file still in the inbox is
  read: it is not the deployment's yet and has no location until it is.
  """
  @spec probe_file(Path.t()) ::
          {:ok, map()} | {:error, {:ffprobe, non_neg_integer(), String.t()}}
  def probe_file(path) do
    args = ~w(-v error -print_format json -show_format -show_streams -show_chapters)

    case System.cmd(ffprobe!(), args ++ [path], stderr_to_stdout: true) do
      {output, 0} -> {:ok, Jason.decode!(output)}
      {output, status} -> {:error, {:ffprobe, status, String.trim(output)}}
    end
  end

  defp ffprobe! do
    System.find_executable("ffprobe") ||
      raise "the ffprobe executable is not on the PATH; identification needs it"
  end
end
