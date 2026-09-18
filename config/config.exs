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
  queues: [integrity: 2, lifecycle: 1, ingest: 1, analysis: 2],
  cron: [
    crontab: [
      # spec-04 §3: each stage is scheduled work finding its own due items.
      {"* * * * *", Pluteus.Workers.AcquireFromInbox},
      {"* * * * *", Pluteus.Workers.IdentifyAcquisitions},
      {"* * * * *", Pluteus.Workers.PlaceAcquisitions},
      {"* * * * *", Pluteus.Workers.NormalizeHoldings},
      {"*/5 * * * *", Pluteus.Workers.ScheduleAnalysis},
      {"30 4 * * *", Pluteus.Workers.FindStrayBytes},
      # spec-03 §5.2: verification is scheduled, not incidental.
      {"0 * * * *", Pluteus.Workers.ScheduleVerification},
      # spec-01 §14.1: the recycle-bin window closes on its own.
      {"0 3 * * *", Pluteus.Workers.PurgeExpired}
    ]
  ]

# spec-04 §4.1. A file is acquired once its size and modification time have
# held for the settle interval; a minute outlasts the pauses of a slow network
# copy without leaving a finished file waiting long.
#
# spec-03 §3.2: each asset is verified at the interval configured for its
# broad class.
config :pluteus, Pluteus.Ingest,
  settle_seconds: 60,
  verification_interval_seconds: %{
    audio: 90 * 86_400,
    video: 90 * 86_400,
    image: 90 * 86_400,
    text: 90 * 86_400,
    companion: 90 * 86_400
  }

# spec-04 §8. The deriving tools that run, and the wire schema versions a tool
# response may carry.
config :pluteus, Pluteus.Analysis,
  tools: [Pluteus.Analysis.Native, Pluteus.Analysis.Sidecar],
  schema_versions: [1]

# Beat tracking and constant-Q analysis of a long recording take a while; the
# timeout bounds one request, and a timeout is a transient failure.
config :pluteus, Pluteus.Analysis.Sidecar, url: "http://sidecar:8000", timeout_ms: 600_000

# Identity arrives from a reverse proxy running forward auth. The subject is
# the email address the provider sends, which is not stable across an email
# change; spec-06 §3.2 records the consequence. Header names are lowercase, as
# Plug holds them.
config :pluteus, PluteusWeb.ForwardAuth,
  subject_header: "x-authentik-email",
  secret_header: "x-pluteus-proxy-secret"

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
