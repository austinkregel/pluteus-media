defmodule Pluteus.Corpus.Geonames do
  @moduledoc """
  Imports a verified snapshot of GeoNames into the corpora's database (spec-05 §5.7,
  §9.7).

  **A lookup reads one whole snapshot or the other.** The new snapshot is loaded into a
  staging schema shaped like `geonames`, and in the same transaction the two are exchanged
  and the snapshot is marked imported. A lookup running alongside sees the snapshot that was
  in use until the transaction commits, and the new one after; an import that fails rolls
  back to the snapshot it started from, staging schema and all.

  **The files are loaded as the publisher wrote them.** They are tab-separated UTF-8 with
  no header row, and a name may hold a double quote or a backslash. They are read as CSV
  delimited by tabs with a quote character the publisher never writes, so neither is taken
  for syntax; an empty field is absent.

  Once imported, the snapshot's downloaded files are removed: they are kept until they are
  imported and no longer.
  """

  alias Ecto.Adapters.SQL
  alias Pluteus.Corpus
  alias Pluteus.Corpus.Repo
  alias Pluteus.Corpus.Snapshot

  @corpus "geonames"

  # Each table, the file it is loaded from — inside the archive where the publisher zips
  # it, or after the comment lines the publisher opens it with — and its columns in the
  # order the publisher gives them.
  @tables [
    {"places", {:zipped, "allCountries.zip", "allCountries.txt"},
     ~w(geonameid name asciiname alternatenames latitude longitude feature_class feature_code
        country_code cc2 admin1_code admin2_code admin3_code admin4_code population elevation
        dem timezone modified_on)},
    {"admin1", {:plain, "admin1CodesASCII.txt"}, ~w(code name asciiname geonameid)},
    {"admin2", {:plain, "admin2Codes.txt"}, ~w(code name asciiname geonameid)},
    {"countries", {:commented, "countryInfo.txt"},
     ~w(iso iso3 iso_numeric fips name capital area_square_km population continent tld
        currency_code currency_name phone postal_code_format postal_code_regex languages
        geonameid neighbours equivalent_fips_code)}
  ]

  @doc """
  Imports a verified snapshot, making it the one lookups read.
  """
  @spec import_snapshot(Snapshot.t()) :: Snapshot.t()
  def import_snapshot(%Snapshot{corpus: @corpus, state: :verified} = snapshot) do
    directory = Corpus.snapshot_directory(@corpus, snapshot.stated_on)

    {:ok, imported} =
      Repo.transaction(
        fn ->
          Repo.query!("CREATE SCHEMA geonames_incoming")

          for {table, source, columns} <- @tables do
            Repo.query!(
              "CREATE TABLE geonames_incoming.#{table} (LIKE geonames.#{table} INCLUDING ALL)"
            )

            load(table, columns, rows(directory, source))
          end

          Repo.query!("ALTER SCHEMA geonames RENAME TO geonames_previous")
          Repo.query!("ALTER SCHEMA geonames_incoming RENAME TO geonames")
          Repo.query!("DROP SCHEMA geonames_previous CASCADE")

          Corpus.imported(snapshot)
        end,
        timeout: :infinity
      )

    File.rm_rf!(directory)
    imported
  end

  # The bytes to load, as a stream: a zipped file extracted beside its archive and read in
  # blocks, a plain one read in blocks, and a commented one read by line with every line the
  # publisher marked as a comment left out — its column header among them.
  defp rows(directory, {:zipped, archive, entry}) do
    {:ok, [extracted]} =
      :zip.extract(String.to_charlist(Path.join(directory, archive)),
        cwd: String.to_charlist(directory),
        file_list: [String.to_charlist(entry)]
      )

    extracted |> to_string() |> File.stream!(1_048_576)
  end

  defp rows(directory, {:plain, file}),
    do: directory |> Path.join(file) |> File.stream!(1_048_576)

  defp rows(directory, {:commented, file}) do
    directory
    |> Path.join(file)
    |> File.stream!(:line)
    |> Stream.reject(&String.starts_with?(&1, "#"))
  end

  defp load(table, columns, rows) do
    copy =
      SQL.stream(
        Repo,
        "COPY geonames_incoming.#{table} (#{Enum.join(columns, ", ")}) FROM STDIN " <>
          "WITH (FORMAT csv, DELIMITER E'\\t', QUOTE E'\\x01', NULL '')"
      )

    Enum.into(rows, copy)
  end
end
