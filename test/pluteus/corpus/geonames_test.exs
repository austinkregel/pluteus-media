defmodule Pluteus.Corpus.GeonamesTest do
  @moduledoc """
  GeoNames is fetched, verified by size, and imported whole or not at all (spec-05 §5.7),
  so that a coordinate is answered from a copy the household holds (§9.7, criterion 31).

  Against a real HTTP server on this host serving a small dump laid out as the publisher
  lays out its own, because what is under test is what a publisher announces and what the
  fetch and the import make of it.

  Not async: an import exchanges the `geonames` schema itself, which no other test may be
  reading at the time.
  """

  use Pluteus.DataCase, async: false

  alias Pluteus.Corpus
  alias Pluteus.Corpus.Acquire
  alias Pluteus.Corpus.Fetch
  alias Pluteus.Corpus.Geonames
  alias Pluteus.Corpus.Repo, as: CorpusRepo
  alias Pluteus.Ingest

  @corpus "geonames"

  # A row of the publisher's geoname table, its nineteen columns in the readme's order:
  # geonameid, name, asciiname, alternatenames, latitude, longitude, feature class, feature
  # code, country code, cc2, admin1 to admin4, population, elevation, dem, timezone, and
  # modification date. Elevation is left empty, as the publisher leaves it for most places.
  defp row(geonameid, name, {latitude, longitude}, {class, code}, admin2, population) do
    [
      geonameid,
      name,
      name,
      "",
      latitude,
      longitude,
      class,
      code,
      "US",
      "",
      "MI",
      admin2,
      "",
      "",
      population,
      "",
      "200",
      "America/Detroit",
      "2024-01-01"
    ]
  end

  defp grand_rapids,
    do: row("4994358", "Grand Rapids", {"42.96336", "-85.66809"}, {"P", "PPLA2"}, "081", "198917")

  defp walker,
    do: row("5014681", "Walker", {"42.99836", "-85.76809"}, {"P", "PPL"}, "081", "25132")

  defp michigan,
    do: row("5001836", "Michigan", {"44.25029", "-85.50033"}, {"A", "ADM1"}, "", "10077331")

  defp lake, do: row("4996890", "Lake Michigan", {"44.0", "-87.0"}, {"H", "LK"}, "", "0")

  # A name holding both characters a text-format COPY would take for syntax.
  defp corner,
    do: row("5000001", ~S(O"Neil's \ Corner), {"42.9", "-85.6"}, {"P", "PPL"}, "081", "0")

  defmodule Server do
    @moduledoc false
    import Plug.Conn

    def init(files), do: files

    # Serves `/<snapshot>/<file>` from what the test put in the agent: a body, and the
    # last-modified time it announces. `/changing/` answers HEAD from one body and GET
    # from another, as a file regenerated between the two would.
    def call(conn, files) do
      ["", snapshot, file] = String.split(conn.request_path, "/")
      {body, last_modified} = Agent.get(files, &Map.fetch!(&1, {snapshot, file, conn.method}))

      conn
      |> put_resp_header("last-modified", http_date(last_modified))
      |> send_resp(200, body)
    end

    defp http_date(datetime), do: Calendar.strftime(datetime, "%a, %d %b %Y %H:%M:%S GMT")
  end

  setup do
    {:ok, files} = Agent.start_link(fn -> %{} end)

    {:ok, server} =
      Bandit.start_link(plug: {Server, files}, ip: {127, 0, 0, 1}, port: 0, startup_log: false)

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)

    on_exit(fn -> File.rm_rf!(Path.join(Corpus.directory(), @corpus)) end)

    %{files: files, origin: "http://127.0.0.1:#{port}"}
  end

  # Publishes a dump under `/<snapshot>/`, every file last modified at `at` unless a file
  # is given a time of its own.
  defp publish(files, snapshot, places, at, overrides \\ %{}) do
    published = %{
      "allCountries.zip" => zipped("allCountries.txt", tsv(places)),
      "admin1CodesASCII.txt" => "US.MI\tMichigan\tMichigan\t5001836\n",
      "admin2Codes.txt" => "US.MI.081\tKent County\tKent County\t4997591\n",
      "countryInfo.txt" => country_info()
    }

    Agent.update(files, fn served ->
      Enum.reduce(published, served, fn {file, body}, served ->
        when_modified = Map.get(overrides, file, at)

        served
        |> Map.put({snapshot, file, "HEAD"}, {body, when_modified})
        |> Map.put({snapshot, file, "GET"}, {body, when_modified})
      end)
    end)
  end

  defp tsv(rows), do: Enum.map_join(rows, &(Enum.join(&1, "\t") <> "\n"))

  # As the publisher opens it: comment lines, the last of them its column header. The data
  # row's postal code format holds a `#` and its pattern a backslash, neither of which marks
  # anything.
  defp country_info do
    "# GeoNames.org Country Information\n" <>
      "# ================================\n" <>
      "#ISO\tISO3\tISO-Numeric\tfips\tCountry\tCapital\tArea(in sq km)\tPopulation\t" <>
      "Continent\ttld\tCurrencyCode\tCurrencyName\tPhone\tPostal Code Format\t" <>
      "Postal Code Regex\tLanguages\tgeonameid\tneighbours\tEquivalentFipsCode\n" <>
      tsv([
        [
          "US",
          "USA",
          "840",
          "US",
          "United States",
          "Washington",
          "9629091.0",
          "327167434",
          "NA",
          ".us",
          "USD",
          "Dollar",
          "1",
          "#####-####",
          ~S|^\d{5}(-\d{4})?$|,
          "en-US,es-US,haw,fr",
          "6252001",
          "CA,MX,CU",
          ""
        ]
      ])
  end

  defp zipped(entry, contents) do
    {:ok, {_name, zip}} =
      :zip.create(~c"allCountries.zip", [{String.to_charlist(entry), contents}], [:memory])

    zip
  end

  defp places do
    CorpusRepo.query!(
      "SELECT geonameid, name, elevation, feature_class FROM geonames.places ORDER BY geonameid"
    ).rows
  end

  defp acquire(origin, snapshot) do
    {:ok, verified} = Acquire.fetch(@corpus, from: "#{origin}/#{snapshot}/")
    Geonames.import_snapshot(verified)
  end

  describe "§5.7. A snapshot is dated by what its publisher announces" do
    test "every file's last-modified date, where they agree", %{files: files, origin: origin} do
      publish(files, "one", [grand_rapids()], ~U[2026-11-06 02:50:44Z])

      assert {:ok, snapshot} = Acquire.fetch(@corpus, from: "#{origin}/one/")
      assert snapshot.stated_on == ~D[2026-11-06]
      assert snapshot.state == :verified

      assert %{"size" => _, "last_modified" => "2026-11-06T02:50:44Z"} =
               snapshot.files["allCountries.zip"]
    end

    test "files dated differently are not one snapshot, and nothing is fetched", %{
      files: files,
      origin: origin
    } do
      publish(files, "split", [grand_rapids()], ~U[2026-11-06 02:50:44Z], %{
        "admin2Codes.txt" => ~U[2026-11-07 02:50:44Z]
      })

      assert {:error, {:dates_disagree, dates}} = Acquire.fetch(@corpus, from: "#{origin}/split/")
      assert dates["admin2Codes.txt"] == ~D[2026-11-07]
      assert Corpus.current(@corpus) == nil
      refute File.exists?(Corpus.snapshot_directory(@corpus, ~D[2026-11-06]))
    end

    test "an answer announcing no date cannot be placed in a snapshot" do
      {:ok, server} =
        Bandit.start_link(
          plug: fn conn, _ -> Plug.Conn.send_resp(conn, 200, "undated") end,
          ip: {127, 0, 0, 1},
          port: 0,
          startup_log: false
        )

      {:ok, {_address, port}} = ThousandIsland.listener_info(server)

      assert Fetch.head("http://127.0.0.1:#{port}/x", user_agent: "pluteus-test") ==
               {:error, {:not_announced, "last-modified"}}
    end
  end

  describe "§5.7. A file is verified before anything reads it" do
    test "a file whose size is not the size announced refuses the snapshot", %{
      files: files,
      origin: origin
    } do
      publish(files, "changing", [grand_rapids()], ~U[2026-11-06 02:50:44Z])

      # Regenerated between the HEAD and the GET: the body fetched is not the one announced.
      Agent.update(files, fn served ->
        Map.put(served, {"changing", "allCountries.zip", "GET"}, {
          zipped("allCountries.txt", tsv([grand_rapids(), walker()])),
          ~U[2026-11-06 02:50:44Z]
        })
      end)

      assert {:refused, refused} = Acquire.fetch(@corpus, from: "#{origin}/changing/")
      assert refused.refused_because == "size_disagrees"
      assert Corpus.current(@corpus) == nil

      assert [finding] = Enum.filter(Ingest.open_findings(), &(&1.corpus == @corpus))
      assert finding.kind == "size_disagrees"
      assert %{"file" => "allCountries.zip", "announced" => _, "fetched" => _} = finding.detail
    end
  end

  describe "§5.7. An import makes a whole snapshot the one lookups read" do
    test "every row as the publisher wrote it, and the downloaded files removed", %{
      files: files,
      origin: origin
    } do
      publish(
        files,
        "one",
        [grand_rapids(), walker(), michigan(), lake(), corner()],
        ~U[2026-11-06 02:50:44Z]
      )

      imported = acquire(origin, "one")

      assert imported.state == :imported
      assert Corpus.current(@corpus).id == imported.id

      assert places() == [
               [4_994_358, "Grand Rapids", nil, "P"],
               [4_996_890, "Lake Michigan", nil, "H"],
               [5_000_001, ~S(O"Neil's \ Corner), nil, "P"],
               [5_001_836, "Michigan", nil, "A"],
               [5_014_681, "Walker", nil, "P"]
             ]

      assert CorpusRepo.query!("SELECT code, name, geonameid FROM geonames.admin1").rows ==
               [["US.MI", "Michigan", 5_001_836]]

      assert CorpusRepo.query!("SELECT code, name FROM geonames.admin2").rows ==
               [["US.MI.081", "Kent County"]]

      assert CorpusRepo.query!(
               "SELECT iso, name, geonameid, postal_code_format, postal_code_regex FROM geonames.countries"
             ).rows == [["US", "United States", 6_252_001, "#####-####", ~S|^\d{5}(-\d{4})?$|]]

      refute File.exists?(Corpus.snapshot_directory(@corpus, ~D[2026-11-06]))
    end

    test "a later snapshot replaces the earlier one whole", %{files: files, origin: origin} do
      publish(files, "earlier", [grand_rapids(), walker()], ~U[2026-10-06 02:50:44Z])
      publish(files, "later", [michigan()], ~U[2026-11-06 02:50:44Z])

      acquire(origin, "earlier")
      later = acquire(origin, "later")

      assert places() == [[5_001_836, "Michigan", nil, "A"]]
      assert Corpus.current(@corpus).id == later.id
    end

    test "the nearest populated place to a coordinate is answered from the index", %{
      files: files,
      origin: origin
    } do
      publish(
        files,
        "one",
        [grand_rapids(), walker(), michigan(), lake()],
        ~U[2026-11-06 02:50:44Z]
      )

      acquire(origin, "one")

      CorpusRepo.query!("SET LOCAL enable_seqscan = off")

      %{rows: plan} =
        CorpusRepo.query!("""
        EXPLAIN SELECT geonameid FROM geonames.places WHERE feature_class = 'P'
        ORDER BY ll_to_earth(latitude, longitude) <-> ll_to_earth(42.97, -85.67) LIMIT 1
        """)

      assert plan |> List.flatten() |> Enum.any?(&(&1 =~ "Index Scan"))
    end

    test "an import that fails leaves the snapshot in use, and no staging schema", %{
      files: files,
      origin: origin
    } do
      publish(files, "good", [grand_rapids()], ~U[2026-10-06 02:50:44Z])
      held = acquire(origin, "good")

      # Eighteen columns where the readme gives nineteen.
      publish(files, "short", [Enum.drop(walker(), -1)], ~U[2026-11-06 02:50:44Z])
      {:ok, verified} = Acquire.fetch(@corpus, from: "#{origin}/short/")

      assert_raise Postgrex.Error, fn -> Geonames.import_snapshot(verified) end

      assert places() == [[4_994_358, "Grand Rapids", nil, "P"]]
      assert Corpus.current(@corpus).id == held.id

      assert CorpusRepo.query!(
               "SELECT count(*) FROM pg_namespace WHERE nspname = 'geonames_incoming'"
             ).rows == [[0]]
    end
  end

  describe "§5.6, §12. A corpus is due when its snapshot is old, and not while held back" do
    test "none imported is due" do
      assert Acquire.due?(@corpus, ~D[2026-11-07])
    end

    test "one imported this month is not, and one a month old is" do
      @corpus |> Corpus.begin(~D[2026-10-06]) |> Corpus.verified(%{}) |> Corpus.imported()

      refute Acquire.due?(@corpus, ~D[2026-11-05])
      assert Acquire.due?(@corpus, ~D[2026-11-06])
    end

    test "an open finding against the corpus holds it back until a person clears it" do
      @corpus |> Corpus.begin(~D[2026-11-06]) |> Corpus.refused("size_disagrees", %{})

      refute Acquire.due?(@corpus, ~D[2026-12-07])
    end
  end
end
