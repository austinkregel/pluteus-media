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

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :pluteus, PluteusWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "tFUMUMAbmai5feQMvsNvsIqf4Mqvm77mvGgpG59V9D8TES9OgtfXVSpxhHhB/5fY",
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

config :pluteus, Pluteus.Ingest,
  settle_seconds: 60,
  verification_interval_seconds: %{
    audio: 90 * 86_400,
    video: 90 * 86_400,
    image: 90 * 86_400,
    text: 90 * 86_400,
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
