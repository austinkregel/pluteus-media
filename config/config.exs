# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :pluteus,
  ecto_repos: [Pluteus.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Background work. Concurrency is set here and nowhere else: a worker never
# spawns its own pool. Verification reads whole files, so two at a time keeps
# the disks from thrashing while a pass over a large library still progresses.
config :pluteus, Oban,
  engine: Oban.Engines.Basic,
  repo: Pluteus.Repo,
  queues: [integrity: 2, lifecycle: 1],
  cron: [
    crontab: [
      # spec-03 §5.2: verification is scheduled, not incidental.
      {"0 * * * *", Pluteus.Workers.ScheduleVerification},
      # spec-01 §14.1: the recycle-bin window closes on its own.
      {"0 3 * * *", Pluteus.Workers.PurgeExpired}
    ]
  ]

# Configure the endpoint
config :pluteus, PluteusWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PluteusWeb.ErrorHTML, json: PluteusWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Pluteus.PubSub,
  live_view: [signing_salt: "Zu6C94T6"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  pluteus: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  pluteus: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
