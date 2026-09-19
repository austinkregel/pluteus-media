defmodule Pluteus.Ingest.Cue do
  @moduledoc """
  Reads a cue sheet: the file it describes, the release's title and performer,
  and where each track starts (spec-04 §6.4).

  Text is returned in Unicode normal form C, so a `FILE` line matches the file
  it names whichever form each was written in.

  Cue sheet time is minutes, seconds and frames of 1/75 second. A track starts
  at its `INDEX 01`; the pregap before it, `INDEX 00`, belongs to the track
  before, as players treat it.
  """

  @frames_per_second 75

  @type track :: %{number: pos_integer(), title: String.t() | nil, start_ms: non_neg_integer()}
  @type t :: %{
          file: String.t() | nil,
          title: String.t() | nil,
          performer: String.t() | nil,
          tracks: [track()]
        }

  @doc """
  The sheet's contents. Raises on a track with no `INDEX 01`, which leaves
  nothing to say where it starts.
  """
  @spec parse(binary()) :: t()
  def parse(bytes) do
    bytes
    |> String.replace_prefix(<<0xEF, 0xBB, 0xBF>>, "")
    |> String.normalize(:nfc)
    |> String.split(~r/\r?\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.reduce(%{file: nil, title: nil, performer: nil, tracks: []}, &line/2)
    |> Map.update!(:tracks, fn tracks -> tracks |> Enum.reverse() |> Enum.map(&started!/1) end)
  end

  defp line("FILE " <> rest, sheet), do: %{sheet | file: sheet.file || quoted(rest, :token)}

  defp line("TRACK " <> rest, sheet) do
    [number | _] = String.split(rest)
    {number, ""} = Integer.parse(number)
    %{sheet | tracks: [%{number: number, title: nil, start_ms: nil} | sheet.tracks]}
  end

  defp line("TITLE " <> rest, %{tracks: []} = sheet), do: %{sheet | title: quoted(rest, :line)}

  defp line("TITLE " <> rest, %{tracks: [track | earlier]} = sheet),
    do: %{sheet | tracks: [%{track | title: quoted(rest, :line)} | earlier]}

  defp line("PERFORMER " <> rest, %{tracks: []} = sheet),
    do: %{sheet | performer: quoted(rest, :line)}

  defp line("INDEX 01 " <> time, %{tracks: [track | earlier]} = sheet),
    do: %{sheet | tracks: [%{track | start_ms: milliseconds(time)} | earlier]}

  defp line(_other, sheet), do: sheet

  defp started!(%{start_ms: nil, number: number}),
    do: raise(ArgumentError, "cue sheet track #{number} has no INDEX 01")

  defp started!(track), do: track

  # A quoted value, or a bare one. What follows a closing quote, such as FILE's
  # type, is not part of it. A bare FILE is its first word, since its type
  # follows; a bare TITLE or PERFORMER is the rest of the line.
  defp quoted(rest, extent) do
    case {Regex.run(~r/^"([^"]*)"/, rest), extent} do
      {[_, value], _extent} -> value
      {nil, :token} -> rest |> String.split() |> hd()
      {nil, :line} -> String.trim(rest)
    end
  end

  defp milliseconds(time) do
    [minutes, seconds, frames] =
      time |> String.trim() |> String.split(":") |> Enum.map(&String.to_integer/1)

    div((minutes * 60 + seconds) * 1000 * @frames_per_second + frames * 1000, @frames_per_second)
  end
end
