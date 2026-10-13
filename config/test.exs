import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
# Postgres allows 100 connections by default. `schedulers_online() * 2` asks for
# 128 on this host, so the pool is capped instead. `max_cases` in
# test/test_helper.exs is held to the same number: a sandboxed async test holds
# one connection for its duration, so exceeding the pool only makes tests queue.
config :pluteus, Pluteus.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "db",
  database: "pluteus_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 32,
  # Ingest keys what it records by inbox path, and many tests drop a file at the
  # same relative path into inboxes of their own. Each sandboxed test holds its
  # rows uncommitted, so a second test writing the same key waits until the
  # first finishes; ingest tests run for many seconds, and the wait outlasts the
  # default statement timeout without anything being wrong.
  timeout: 120_000

# The queue's own database, sandboxed like the catalogue's. A test that inserts or drains
# a job holds a connection to this one as well as to that one, so both are checked out per
# test and both must be in manual mode.
config :pluteus, Pluteus.Jobs.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "jobs-db",
  database: "pluteus_test_jobs#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 32,
  log: false,
  timeout: 120_000

# We don't run a server during test. If one is required,
# you can enable the server option below.
# The endpoint runs no listener of its own. A browser-driven test serves it through
# `Pluteus.Proxy`, which is one listener running the endpoint's own pipeline behind the
# headers the authenticating proxy would have set — so there is one connection, and the
# live socket upgrades on it rather than being carried across a second.
#
# `check_origin: false` because that listener answers on a loopback address and a port,
# and the configured url is a bare host; the socket would otherwise refuse its own page.
config :pluteus, PluteusWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "tFUMUMAbmai5feQMvsNvsIqf4Mqvm77mvGgpG59V9D8TES9OgtfXVSpxhHhB/5fY",
  check_origin: false,
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Stored bytes live under the repository's ignored tmp directory, which the
# container sees through the bind mount.
config :pluteus, Pluteus.Storage, root: Path.expand("../tmp/storage/test", __DIR__)

# A small ceiling and a short idle period, so a test can reach both bounds with a
# handful of artefacts rather than with five gigabytes of them.
config :pluteus, Pluteus.Presentation,
  byte_ceiling: 10_000,
  idle_seconds: 3_600,
  eviction_period_seconds: 3_600

config :pluteus, Pluteus.Ingest,
  settle_seconds: 60,
  verification_interval_seconds: %{
    audio: 90 * 86_400,
    video: 90 * 86_400,
    image: 90 * 86_400,
    text: 90 * 86_400,
    package: 90 * 86_400,
    software: 90 * 86_400,
    companion: 90 * 86_400
  },
  inbox: Path.expand("../tmp/inbox/test", __DIR__)

# Jobs are inserted but not run, so a test drives each one explicitly.
config :pluteus, Oban, testing: :manual

config :pluteus, PluteusWeb.ForwardAuth,
  issuer: "https://auth.test",
  secret: "test-proxy-secret"

config :pluteus, announce_onboarding: false

config :pluteus, Pluteus.Changes.Release, start: false, interval: 20

config :pluteus, PluteusWeb.Subsonic.Response, help_url: "https://pluteus.test/devices"
