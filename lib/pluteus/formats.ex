defmodule Pluteus.Formats do
  @moduledoc """
  Identifies the format of stored bytes against PRONOM (spec-03 §6).

  An intact file in a format nothing can decode is lost as thoroughly as a
  corrupt one, so format is tracked in its own right. Identification reads the
  bytes: Siegfried is run over the file and only a match its signatures found in
  the content is accepted. A match on the filename's extension alone is not an
  identification, since the same name can hold anything; such a file, and one
  Siegfried cannot place at all, is recorded as `"UNKNOWN"` — PRONOM's own term
  — so that it stays visible in a report of holdings by format.

  No Elixir package performs PRONOM identification, so this is an
  out-of-process call to the `sf` binary the image installs.
  """

  alias Pluteus.Storage

  @unknown "UNKNOWN"

  @doc """
  The PRONOM identifier of the bytes at a location.

  Returns an error, and never a guess, where the bytes cannot be read.
  """
  @spec identify(String.t()) :: {:ok, String.t()} | {:error, term()}
  def identify(location), do: location |> Storage.path() |> identify_file()

  @doc """
  Identifies a file that is not at a location, which is how a file still in the inbox is
  read: it is not the deployment's yet and has no location until it is.
  """
  @spec identify_file(Path.t()) :: {:ok, String.t()} | {:error, term()}
  def identify_file(path) do
    # Siegfried writes its report to standard output and its complaints to standard
    # error, and the two are kept apart: merged, a complaint about the file lands in
    # front of the JSON and the parse raises instead of the report being read. What a
    # complaint says is in the report as well, under `errors`, which is where the
    # clause below reads it from.
    case System.cmd(siegfried!(), ["-json", path]) do
      {report, 0} -> report |> Jason.decode!() |> from_report()
      {output, status} -> {:error, {:siegfried, status, String.trim(output)}}
    end
  end

  @spec unknown() :: String.t()
  def unknown, do: @unknown

  defp from_report(%{"files" => [%{"errors" => "", "matches" => matches}]}) do
    {:ok, matches |> Enum.find(&(&1["ns"] == "pronom")) |> from_bytes()}
  end

  defp from_report(%{"files" => [%{"errors" => errors}]}) do
    {:error, {:siegfried, errors}}
  end

  defp from_bytes(%{"id" => @unknown}), do: @unknown

  defp from_bytes(%{"id" => id, "warning" => warning}) do
    if String.contains?(warning, "match on extension only"), do: @unknown, else: id
  end

  defp siegfried! do
    System.find_executable("sf") ||
      raise "the sf executable is not on the PATH; format identification needs Siegfried"
  end
end
