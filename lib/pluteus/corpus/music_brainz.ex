defmodule Pluteus.Corpus.MusicBrainz do
  @moduledoc """
  Imports a verified snapshot of MusicBrainz's core dump into the corpora's database
  (spec-05 §5.7, §9.1), one step at a time.

  The dump is tens of millions of rows in a single bzip2 stream, more than one job may
  spend in one run, so the import is a sequence of steps each run by a job of its own, and
  each step leaves in the database or on disk the evidence that it is done:

    1. **Extract.** The tables the registry holds are taken out of the archive in one pass,
       with the schema sequence the dump states. A dump written in another schema is
       refused, since its columns are not the ones the held tables were written for; the
       snapshot in use stays in use, and the refusal is a finding. A staging schema shaped
       like `musicbrainz` is made, and named for the snapshot it belongs to.
    2. **Load.** One table per step, loaded and indexed in one transaction, so a table
       staged is a table whole.
    3. **Exchange.** Once every table is staged, the staging schema and `musicbrainz` are
       exchanged in the same transaction as the snapshot is marked imported. A lookup sees
       the snapshot that was in use until the transaction commits, and the new one after.

  **The tables are loaded as the publisher wrote them**: each archive member is its
  table's `COPY` output, in PostgreSQL's text format, and is read back the same way.

  Once imported, the snapshot's downloaded and extracted files are removed.
  """

  alias Ecto.Adapters.SQL
  alias Pluteus.Corpus
  alias Pluteus.Corpus.Repo
  alias Pluteus.Corpus.Snapshot
  alias Pluteus.Matching.Registry

  @corpus "musicbrainz"
  @archive "mbdump.tar.bz2"
  @staging "musicbrainz_incoming"

  # What a lookup needs of each table, built once its rows are loaded. Every identifier and
  # redirect is unique in the publisher's own schema, so an index here that cannot be made
  # unique is a dump that is not what it claims to be, and the step raises.
  @indexes %{
    "recording" => ["ADD PRIMARY KEY (id)", {:unique, "gid"}],
    "recording_gid_redirect" => ["ADD PRIMARY KEY (gid)"],
    "track" => ["ADD PRIMARY KEY (id)", {:unique, "gid"}, {:index, "medium, position"}],
    "track_gid_redirect" => ["ADD PRIMARY KEY (gid)"],
    "medium" => ["ADD PRIMARY KEY (id)"],
    "medium_cdtoc" => [{:index, "cdtoc"}],
    "cdtoc" => ["ADD PRIMARY KEY (id)", {:index, "discid"}],
    "release" => ["ADD PRIMARY KEY (id)", {:unique, "gid"}],
    "release_gid_redirect" => ["ADD PRIMARY KEY (gid)"],
    "release_group" => ["ADD PRIMARY KEY (id)", {:unique, "gid"}],
    "release_group_gid_redirect" => ["ADD PRIMARY KEY (gid)"],
    "work" => ["ADD PRIMARY KEY (id)", {:unique, "gid"}],
    "work_gid_redirect" => ["ADD PRIMARY KEY (gid)"],
    "isrc" => [{:index, "isrc"}]
  }

  @typedoc "The step a run took, where the import is not yet whole."
  @type step :: :extracted | {:loaded, String.t()}

  @doc """
  Takes the next step of importing a verified snapshot: answers the step taken, the
  snapshot refused where its dump is in a schema the held tables were not written for, or
  the snapshot imported once the last step is taken.
  """
  @spec import_snapshot(Snapshot.t()) :: {:continuing, step()} | Snapshot.t()
  def import_snapshot(%Snapshot{corpus: @corpus, state: :verified} = snapshot) do
    directory = Corpus.snapshot_directory(@corpus, snapshot.stated_on)
    extracted = Path.join(directory, "extracted")
    %{tables: tables} = Registry.dump!(@corpus)

    if File.dir?(extracted) do
      case Enum.reject(tables, &(&1 in staged(snapshot))) do
        [table | _rest] ->
          load(table, extracted)
          {:continuing, {:loaded, table}}

        [] ->
          exchange(snapshot, directory)
      end
    else
      extract(snapshot, directory, extracted, tables)
    end
  end

  defp extract(snapshot, directory, extracted, tables) do
    extracting = Path.join(directory, "extracting")
    File.rm_rf!(extracting)
    File.mkdir_p!(extracting)

    members = ["SCHEMA_SEQUENCE" | Enum.map(tables, &("mbdump/" <> &1))]
    archive = Path.join(directory, @archive)

    case System.cmd("tar", ["-xjf", archive, "-C", extracting | members], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> raise "extracting #{archive} exited #{status}: #{output}"
    end

    %{schema_sequence: held_for} = Registry.dump!(@corpus)
    stated = extracting |> Path.join("SCHEMA_SEQUENCE") |> File.read!() |> String.trim()

    if stated == Integer.to_string(held_for) do
      File.rename!(extracting, extracted)
      stage(snapshot)
      {:continuing, :extracted}
    else
      File.rm_rf!(extracting)

      Corpus.refused(snapshot, "schema_sequence_differs", %{
        "stated" => stated,
        "held_for" => held_for
      })
    end
  end

  # A staging schema left by another snapshot's import is not this one's, and goes.
  defp stage(snapshot) do
    {:ok, _} =
      Repo.transaction(fn ->
        Repo.query!("DROP SCHEMA IF EXISTS #{@staging} CASCADE")
        Repo.query!("CREATE SCHEMA #{@staging}")
        Repo.query!("COMMENT ON SCHEMA #{@staging} IS '#{snapshot.id}'")
      end)
  end

  # The tables staged so far, which are whole: each is made, loaded and indexed in one
  # transaction. A staging schema belonging to another snapshot is not this one's to
  # continue, and raises.
  defp staged(snapshot) do
    %{rows: [[owner]]} =
      Repo.query!(
        "SELECT obj_description(oid, 'pg_namespace') FROM pg_namespace WHERE nspname = $1",
        [@staging]
      )

    if owner != Integer.to_string(snapshot.id) do
      raise "#{@staging} belongs to snapshot #{inspect(owner)}, not #{snapshot.id}"
    end

    %{rows: rows} =
      Repo.query!("SELECT table_name FROM information_schema.tables WHERE table_schema = $1", [
        @staging
      ])

    List.flatten(rows)
  end

  defp load(table, extracted) do
    {:ok, _} =
      Repo.transaction(
        fn ->
          Repo.query!("CREATE TABLE #{@staging}.#{table} (LIKE musicbrainz.#{table})")
          %SQL.Stream{} = copy(table, Path.join([extracted, "mbdump", table]))
          Repo.query!("SET LOCAL maintenance_work_mem = '1GB'")
          for index <- Map.fetch!(@indexes, table), do: Repo.query!(indexed(table, index))
        end,
        timeout: :infinity
      )
  end

  defp copy(table, path) do
    rows = File.stream!(path, 1_048_576)
    Enum.into(rows, SQL.stream(Repo, "COPY #{@staging}.#{table} FROM STDIN"))
  end

  defp indexed(table, "ADD " <> _rest = constraint),
    do: "ALTER TABLE #{@staging}.#{table} #{constraint}"

  defp indexed(table, {:unique, columns}),
    do: "CREATE UNIQUE INDEX ON #{@staging}.#{table} (#{columns})"

  defp indexed(table, {:index, columns}), do: "CREATE INDEX ON #{@staging}.#{table} (#{columns})"

  defp exchange(snapshot, directory) do
    {:ok, imported} =
      Repo.transaction(fn ->
        Repo.query!("ALTER SCHEMA musicbrainz RENAME TO musicbrainz_previous")
        Repo.query!("ALTER SCHEMA #{@staging} RENAME TO musicbrainz")
        Repo.query!("DROP SCHEMA musicbrainz_previous CASCADE")
        Corpus.imported(snapshot)
      end)

    File.rm_rf!(directory)
    imported
  end
end
