defmodule Pluteus.Ingest.Plexmatch do
  @moduledoc """
  A match file that names a show and says which of its episodes each file is.

  The format is a media manager's, like a cue sheet, and `Pluteus.Ingest.Cue` is its
  sibling here: lines of `Field: value`, where one field repeats and carries a member.

      Title: King of the Hill
      Year: 1997
      TvdbId: 73903
      Episode: S14E01: Season 14/King of the Hill - S14E01 - Return of the King.mkv

  An `Episode` line names a file **by path relative to the directory the match file sits
  in**, which is what lets one document at the top of a show speak for every season under
  it. Its season and episode are stated rather than inferred, and a line stating a season
  and no episode states only the season.

  Nothing here is guessed. A line that is not of this shape is not a member, and a file
  the document does not name is a file the document says nothing about.
  """

  @typedoc """
  What a match file states: its own fields, and the member each `Episode` line names.
  """
  @type t :: %{
          fields: %{String.t() => String.t()},
          members: [
            %{
              season: pos_integer(),
              episode: pos_integer() | nil,
              path: String.t()
            }
          ]
        }

  @doc """
  Reads a match file.

  A file carrying none of this shape reads as no fields and no members, which is what a
  document that states nothing is.
  """
  @spec read(binary()) :: t()
  def read(bytes) when is_binary(bytes) do
    stated =
      bytes
      |> String.split(~r/\r?\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&stated/1)
      |> Enum.reject(&is_nil/1)

    %{fields: fields(stated), members: for({:member, member} <- stated, do: member)}
  end

  # A field appearing more than once keeps the first, as a document's fields do.
  defp fields(stated) do
    Enum.reduce(stated, %{}, fn
      {:field, {name, value}}, carried -> Map.put_new(carried, name, value)
      {:member, _member}, carried -> carried
    end)
  end

  @doc """
  Which member of a match file names the given path, or nil.

  The path is the one the file sits at relative to the match file's own directory, which
  is how the document writes it.
  """
  @spec member_at(t(), String.t()) :: map() | nil
  def member_at(%{members: members}, path) do
    Enum.find(members, &(String.downcase(&1.path) == String.downcase(path)))
  end

  defp stated(""), do: nil

  defp stated(line) do
    case String.split(line, ":", parts: 2) do
      [name, rest] -> named(String.downcase(String.trim(name)), String.trim(rest))
      _not_a_field -> nil
    end
  end

  # An episode line carries a member rather than a value: `S14E01: <path>`.
  defp named("episode", rest), do: member(rest)
  defp named("", _rest), do: nil
  defp named(name, value), do: {:field, {name, value}}

  defp member(rest) do
    with [marker, path] <- String.split(rest, ":", parts: 2),
         %{"season" => season} = taken <- numbered(String.trim(marker)) do
      {:member,
       %{
         season: String.to_integer(season),
         episode: numeral(taken["episode"]),
         path: String.trim(path)
       }}
    else
      _not_a_member -> nil
    end
  end

  defp numbered(marker),
    do: Regex.named_captures(~r/^s(?<season>\d+)(e(?<episode>\d+))?$/i, marker)

  # A line stating a season and no episode states only the season, and the capture that
  # did not take part comes back empty rather than absent.
  defp numeral(""), do: nil
  defp numeral(digits), do: String.to_integer(digits)
end
