defmodule Pluteus.Corpus.MusicBrainzTest do
  @moduledoc """
  MusicBrainz's core dump is fetched from the export its publisher's `LATEST` names,
  verified against the SHA-256 the export states for it (spec-05 §5.7), and imported
  whole or not at all.

  Against a real HTTP server on this host laid out as the publisher lays out its full
  exports, because what is under test is what a publisher states and what the fetch makes
  of it.

  Not async: an import exchanges the `musicbrainz` schema itself, which no other test may
  be reading at the time.
  """

  use Pluteus.DataCase, async: false

  import Pluteus.MusicBrainzFixtures

  alias Pluteus.Corpus
  alias Pluteus.Corpus.Acquire
  alias Pluteus.Corpus.MusicBrainz
  alias Pluteus.Corpus.Repo, as: CorpusRepo
  alias Pluteus.Ingest
  alias Pluteus.Matching.Registry

  @corpus "musicbrainz"
  @archive "mbdump.tar.bz2"

  defmodule Server do
    @moduledoc false
    import Plug.Conn

    def init(served), do: served

    # Serves whatever path the test put in the agent, with the last-modified time it
    # announces.
    def call(conn, served) do
      {body, last_modified} = Agent.get(served, &Map.fetch!(&1, conn.request_path))

      conn
      |> put_resp_header("last-modified", http_date(last_modified))
      |> send_resp(200, body)
    end

    defp http_date(datetime), do: Calendar.strftime(datetime, "%a, %d %b %Y %H:%M:%S GMT")
  end

  setup do
    {:ok, served} = Agent.start_link(fn -> %{} end)

    {:ok, server} =
      Bandit.start_link(plug: {Server, served}, ip: {127, 0, 0, 1}, port: 0, startup_log: false)

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)

    on_exit(fn -> File.rm_rf!(Path.join(Corpus.directory(), @corpus)) end)

    %{served: served, from: "http://127.0.0.1:#{port}/fullexport/"}
  end

  @at ~U[2026-11-04 01:57:46Z]

  # An export under `/fullexport/<directory>/`, with the checksum file the publisher writes
  # beside it, and `LATEST` naming it.
  defp export(served, directory, archive, stated \\ nil) do
    digest = stated || sha256(archive)

    checksums =
      "5fb91e9141a45ffa58e8df5de7bc6274486726feaed417516c3d83b6cd7ca311 *mbdump-cdstubs.tar.bz2\n" <>
        "#{digest} *#{@archive}\n"

    serve(served, %{
      "/fullexport/LATEST" => directory <> "\n",
      "/fullexport/#{directory}/SHA256SUMS" => checksums,
      "/fullexport/#{directory}/#{@archive}" => archive
    })
  end

  defp serve(served, paths) do
    Agent.update(served, fn held ->
      Enum.reduce(paths, held, fn {path, body}, held -> Map.put(held, path, {body, @at}) end)
    end)
  end

  defp sha256(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)

  describe "§5.7. A snapshot is the export LATEST names, verified by its stated digest" do
    test "dated by the directory's name, and recorded with the digest it agreed with", %{
      served: served,
      from: from
    } do
      export(served, "20261104-002222", "the archive")

      assert {:ok, snapshot} = Acquire.fetch(@corpus, from: from)
      assert snapshot.stated_on == ~D[2026-11-04]
      assert snapshot.state == :verified

      assert snapshot.files[@archive] == %{
               "url" => from <> "20261104-002222/" <> @archive,
               "size" => byte_size("the archive"),
               "last_modified" => "2026-11-04T01:57:46Z",
               "sha256" => sha256("the archive")
             }
    end

    test "an archive whose digest is not the one stated refuses the snapshot", %{
      served: served,
      from: from
    } do
      export(served, "20261104-002222", "the archive", sha256("another archive"))

      assert {:refused, refused} = Acquire.fetch(@corpus, from: from)
      assert refused.refused_because == "digest_disagrees"
      assert Corpus.current(@corpus) == nil

      assert [finding] = Enum.filter(Ingest.open_findings(), &(&1.corpus == @corpus))
      assert finding.kind == "digest_disagrees"

      assert %{"file" => @archive, "stated" => stated, "fetched" => fetched} = finding.detail
      assert stated == sha256("another archive")
      assert fetched == sha256("the archive")
    end

    test "a checksum file stating nothing for the archive begins nothing", %{
      served: served,
      from: from
    } do
      export(served, "20261104-002222", "the archive")

      serve(served, %{
        "/fullexport/20261104-002222/SHA256SUMS" =>
          "5fb91e9141a45ffa58e8df5de7bc6274486726feaed417516c3d83b6cd7ca311 *mbdump-cdstubs.tar.bz2\n"
      })

      assert Acquire.begin(@corpus, from: from) == {:error, {:no_checksum, @archive}}
      assert Corpus.Repo.aggregate(Corpus.Snapshot, :count) == 0
    end

    test "a pointer naming no export time begins nothing", %{served: served, from: from} do
      serve(served, %{"/fullexport/LATEST" => "latest\n"})

      assert Acquire.begin(@corpus, from: from) == {:error, {:pointer_names_no_date, "latest"}}
      assert Corpus.Repo.aggregate(Corpus.Snapshot, :count) == 0
    end

    test "an archive fetched over several jobs comes from the export it began in", %{
      served: served,
      from: from
    } do
      export(served, "20261104-002222", "the archive")
      {:ok, snapshot, [{@archive, said}]} = Acquire.begin(@corpus, from: from)

      assert :paused =
               Acquire.fetch_file(snapshot, @archive, said,
                 until: System.monotonic_time(:millisecond) - 1
               )

      # The publisher's next export, begun while this one was still arriving.
      export(served, "20261107-002315", "a newer archive")

      assert {:verified, verified} = Acquire.fetch_file(snapshot, @archive, said)
      assert verified.stated_on == ~D[2026-11-04]
      assert verified.files[@archive]["sha256"] == sha256("the archive")
    end
  end

  @earlier "f3d4c7a2-1b0e-4c5d-8e9f-0a1b2c3d4e5f"
  @later "0b1c2d3e-4f50-4a6b-9c7d-8e9fa0b1c2d3"

  # A name holding the characters PostgreSQL's text format escapes.
  @escaped "Tab\there, back\\slash"

  defp rows(recording_gid, name) do
    %{
      "recording" => [recording(1, recording_gid, name)],
      "cdtoc" => [cdtoc(7, "49HHV7Eb8UKF3aQiNmu1GR8vKTY-", 95_462, [150, 15_363, 32_314])]
    }
  end

  defp recordings,
    do: CorpusRepo.query!("SELECT gid::text, name FROM musicbrainz.recording ORDER BY id").rows

  describe "§5.7. An import makes a whole snapshot the one lookups read, a step at a time" do
    test "the tables are taken out, each loaded in a step of its own, then exchanged" do
      snapshot = rows(@earlier, @escaped) |> dump() |> verified(~D[2026-11-04])
      directory = Corpus.snapshot_directory(@corpus, ~D[2026-11-04])

      assert MusicBrainz.import_snapshot(snapshot) == {:continuing, :extracted}

      for table <- Registry.dump!(@corpus).tables do
        assert MusicBrainz.import_snapshot(snapshot) == {:continuing, {:loaded, table}}
      end

      assert %{state: :imported} = imported = MusicBrainz.import_snapshot(snapshot)
      assert Corpus.current(@corpus).id == imported.id

      assert recordings() == [[@earlier, @escaped]]

      assert CorpusRepo.query!(
               "SELECT discid, leadout_offset, track_offset FROM musicbrainz.cdtoc"
             ).rows ==
               [["49HHV7Eb8UKF3aQiNmu1GR8vKTY-", 95_462, [150, 15_363, 32_314]]]

      refute File.exists?(directory)
    end

    test "a lookup reads the snapshot in use until the exchange, and the new one after" do
      held!(rows(@earlier, "Earlier"), ~D[2026-10-04])
      later = rows(@later, "Later") |> dump() |> verified(~D[2026-11-04])

      for _step <- 0..length(Registry.dump!(@corpus).tables) do
        assert {:continuing, _step} = MusicBrainz.import_snapshot(later)
        assert recordings() == [[@earlier, "Earlier"]]
      end

      assert %{state: :imported} = MusicBrainz.import_snapshot(later)
      assert recordings() == [[@later, "Later"]]
    end

    test "a dump in another schema is refused, and the snapshot in use stays in use" do
      held = held!(rows(@earlier, "Earlier"), ~D[2026-10-04])
      other = rows(@later, "Later") |> dump(30) |> verified(~D[2026-11-04])

      assert %{state: :refused, refused_because: "schema_sequence_differs"} =
               MusicBrainz.import_snapshot(other)

      assert Corpus.current(@corpus).id == held.id
      assert recordings() == [[@earlier, "Earlier"]]

      assert [finding] = Enum.filter(Ingest.open_findings(), &(&1.corpus == @corpus))
      assert %{"stated" => "30", "held_for" => 31} = finding.detail
    end

    test "a staging schema another snapshot's import made is not continued" do
      first = rows(@earlier, "Earlier") |> dump() |> verified(~D[2026-10-04])
      second = rows(@later, "Later") |> dump() |> verified(~D[2026-11-04])

      assert {:continuing, :extracted} = MusicBrainz.import_snapshot(first)
      assert {:continuing, :extracted} = MusicBrainz.import_snapshot(second)

      assert_raise RuntimeError, ~r/belongs to snapshot/, fn ->
        MusicBrainz.import_snapshot(first)
      end
    end
  end
end
