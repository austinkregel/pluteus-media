ExUnit.start(max_cases: 32)

# The sandbox rolls a test's rows back and cannot roll its bytes back: a test that
# ingests a file writes it through the real pipeline, and the file outlives the
# transaction that accounted for it. Left alone the scratch root grows by every asset
# every run has ever written, and `Ingest.find_stray_bytes/1` reads all of it — so a
# stray-bytes assertion starts answering for years of leavings rather than for the test.
#
# The root is scratch, configured under `tmp/`, so the run starts from nothing.
File.rm_rf!(Pluteus.Storage.root())

# Emptying it took the evidence that it is there. A test root is a directory this run
# owns rather than a volume it mounts, so it places its own.
Pluteus.Storage.Mount.mark!()

# A deployment has exactly one System principal, and every sandboxed test that
# made its own would wait on that uniqueness for every other test holding one
# uncommitted. It is made once, committed, before any test runs.
case Pluteus.Repo.get_by(Pluteus.Principals.Principal, role: "system") do
  nil -> {:ok, _} = Pluteus.Principals.create_principal(%{role: "system"})
  _system -> :ok
end

# Placement takes the probe's tool-version row before anything else, deliberately: two
# placements contending for it is what makes one release out of two tracks arriving
# together (spec-04 §6.4). Under the sandbox no test's transaction ever commits, so the
# first placing test to insert that row holds it for its whole duration and every other
# placing test waits — which a slow test turns into a timeout somewhere else. It is
# made once, committed, before any test runs, so placement finds it instead of taking it.
case Pluteus.Annotations.record_tool_version("ffprobe", Pluteus.Ingest.Streams.ffprobe_version()) do
  {:ok, _version} -> :ok
  {:error, reason} -> raise "the probe's tool version could not be recorded: #{inspect(reason)}"
end

Ecto.Adapters.SQL.Sandbox.mode(Pluteus.Repo, :manual)
Ecto.Adapters.SQL.Sandbox.mode(Pluteus.Jobs.Repo, :manual)
Ecto.Adapters.SQL.Sandbox.mode(Pluteus.Corpus.Repo, :manual)

# Fetched corpus files outlive the transaction that recorded them, as stored bytes do, so
# their scratch directory starts each run empty too.
File.rm_rf!(Pluteus.Corpus.directory())

# The one listener a browser-driven test reaches the interface through. It serves the
# endpoint's own pipeline behind the headers the authenticating proxy would have set, so
# nothing is bypassed and nothing is forwarded twice.
#
# Started for every run rather than for the tests that use it, because a listener nobody
# connects to costs a port and an idle acceptor. The port is the endpoint's configured
# one; a partitioned run would need it varied as the database names already are.
{:ok, _listener} =
  Bandit.start_link(
    plug: Pluteus.Proxy,
    scheme: :http,
    ip: {127, 0, 0, 1},
    port: Pluteus.Proxy.port()
  )
