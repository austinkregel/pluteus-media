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
  pool_size: 32

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

# Jobs are inserted but not run, so a test drives each one explicitly.
config :pluteus, Oban, testing: :manual
