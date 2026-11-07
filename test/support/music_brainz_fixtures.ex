defmodule Pluteus.MusicBrainzFixtures do
  @moduledoc """
  MusicBrainz core dumps, small and laid out as the publisher lays out its own: a bzip2
  tar holding `SCHEMA_SEQUENCE` and one `mbdump/<table>` member per table, each its
  table's `COPY` output in PostgreSQL's text format.

  Rows are given per table as lists of column values in the dump's column order, with
  `nil` for a null. A table given no rows is in the archive and empty, as a table the
  publisher holds nothing in would be.
  """

  alias Pluteus.Corpus
  alias Pluteus.Corpus.MusicBrainz
  alias Pluteus.Corpus.Snapshot
  alias Pluteus.Matching.Registry

  @corpus "musicbrainz"

  @doc """
  An archive holding `rows`, built by tar and bzip2 as the publisher's is, so the import
  under test reads the format it reads in production. The schema sequence it states is
  the one the held tables are written for unless one is given, which is how a dump from
  another schema is made.
  """
  @spec dump(%{String.t() => [list()]}, pos_integer()) :: binary()
  def dump(rows, schema_sequence \\ Registry.dump!(@corpus).schema_sequence) do
    root =
      Path.join(System.tmp_dir!(), "mbdump-#{System.unique_integer([:positive])}-#{:os.getpid()}")

    File.mkdir_p!(Path.join(root, "mbdump"))
    File.write!(Path.join(root, "SCHEMA_SEQUENCE"), "#{schema_sequence}\n")
    File.write!(Path.join(root, "TIMESTAMP"), "2026-11-04 00:22:23.0+00\n")

    for table <- Registry.dump!(@corpus).tables do
      File.write!(Path.join([root, "mbdump", table]), copied(Map.get(rows, table, [])))
    end

    archive = root <> ".tar.bz2"

    {_, 0} =
      System.cmd("tar", ["-cjf", archive, "-C", root, "TIMESTAMP", "SCHEMA_SEQUENCE", "mbdump"])

    bytes = File.read!(archive)
    File.rm_rf!(root)
    File.rm!(archive)
    bytes
  end

  @doc """
  A snapshot dated `stated_on`, verified, with `archive` placed where its fetch would
  have left it.
  """
  @spec verified(binary(), Date.t()) :: Snapshot.t()
  def verified(archive, stated_on) do
    directory = Corpus.snapshot_directory(@corpus, stated_on)
    File.mkdir_p!(directory)
    File.write!(Path.join(directory, "mbdump.tar.bz2"), archive)

    @corpus
    |> Corpus.begin(stated_on)
    |> Corpus.verified(%{"mbdump.tar.bz2" => %{"size" => byte_size(archive)}})
  end

  @doc """
  Imports `rows` as the MusicBrainz snapshot in use, taking every step.
  """
  @spec held!(%{String.t() => [list()]}, Date.t()) :: Snapshot.t()
  def held!(rows, stated_on \\ ~D[2026-11-04]) do
    rows |> dump() |> verified(stated_on) |> import_whole()
  end

  @doc """
  Takes every step of importing a verified snapshot.
  """
  @spec import_whole(Snapshot.t()) :: Snapshot.t()
  def import_whole(%Snapshot{} = snapshot) do
    case MusicBrainz.import_snapshot(snapshot) do
      {:continuing, _step} -> import_whole(snapshot)
      %Snapshot{} = finished -> finished
    end
  end

  # PostgreSQL's text format: tab-separated, `\N` for a null, and a backslash, tab,
  # newline or carriage return in a value escaped with a backslash.
  defp copied(rows),
    do: Enum.map_join(rows, &(Enum.map_join(&1, "\t", fn v -> field(v) end) <> "\n"))

  defp field(nil), do: "\\N"
  defp field(true), do: "t"
  defp field(false), do: "f"
  defp field(value) when is_integer(value), do: Integer.to_string(value)

  defp field(values) when is_list(values),
    do: "{" <> Enum.map_join(values, ",", &Integer.to_string/1) <> "}"

  defp field(value) when is_binary(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\t", "\\t")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
  end

  @doc "A recording row: id, MBID, name, and nothing else the dump holds."
  def recording(id, gid, name), do: [id, gid, name, 1, nil, "", 0, nil, false]

  @doc "A track row: its position on a medium, and the recording it is."
  def track(id, gid, recording, medium, position, name),
    do: [
      id,
      gid,
      recording,
      medium,
      position,
      Integer.to_string(position),
      name,
      1,
      nil,
      0,
      nil,
      false
    ]

  @doc "A medium row: its position in a release."
  def medium(id, gid, release, position, track_count),
    do: [id, release, position, 1, "", 0, nil, track_count, gid]

  @doc "A release row: its MBID, and the release group it is in."
  def release(id, gid, release_group, name),
    do: [id, gid, name, 1, release_group, 1, nil, nil, nil, nil, "", 0, -1, nil]

  @doc "A release group row."
  def release_group(id, gid, name), do: [id, gid, name, 1, 1, "", 0, nil]

  @doc "A work row."
  def work(id, gid, name), do: [id, gid, name, nil, "", 0, nil]

  @doc "An ISRC row: the recording it was given to."
  def isrc(id, recording, isrc), do: [id, recording, isrc, 0, nil]

  @doc "A disc table of contents: its disc ID, track count, lead-out and track offsets."
  def cdtoc(id, discid, leadout, offsets),
    do: [id, discid, "00000000", length(offsets), leadout, offsets, nil]

  @doc "The table of contents a medium carries."
  def medium_cdtoc(id, medium, cdtoc), do: [id, medium, cdtoc, 0, nil]

  @doc "A redirect from a merged MBID to the row it now belongs to."
  def redirect(gid, new_id), do: [gid, new_id, nil]
end
