# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Two databases, and every ecto task walks this list. The queue's is separate because
# Oban polls whether or not anything is happening, and on one server that work shares a
# connection pool, shared buffers and autovacuum with the request a person is waiting on.
config :pluteus,
  ecto_repos: [Pluteus.Repo, Pluteus.Jobs.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Where this repo's migrations are, in every environment. It belongs here rather than in
# the repo module because that is where `mix ecto.migrate` reads it; left unset it falls
# back to `priv/` plus the module's last segment, which is `repo` — so the queue's
# database would be handed the catalogue's migrations and would take them.
config :pluteus, Pluteus.Jobs.Repo, priv: "priv/jobs_repo"

# Background work. Concurrency is set here and nowhere else: a worker never
# spawns its own pool. Verification reads whole files, so two at a time keeps
# the disks from thrashing while a pass over a large library still progresses.
# spec-07 §5.1: how often the change feed's release is advanced. A push to
# sockets follows each advance, so this is also how long a change can wait
# before a device hears of it.
# [OPENSUBSONIC] apiKeyAuthentication: a client refused for offering a password
# is told where a person can mint a key it would accept. A deployment with
# nowhere to send them says nothing rather than somewhere wrong.
config :pluteus, PluteusWeb.Subsonic.Response, help_url: nil

config :pluteus, Pluteus.Changes.Release, start: true, interval: 1_000

# Off by default. A release replaces `priv` rather than editing it underneath a running
# node, and there is no `assets/` there to write a stylesheet into.
config :pluteus, Pluteus.Design.Watcher, start: false

config :pluteus, Oban,
  engine: Oban.Engines.Basic,
  repo: Pluteus.Jobs.Repo,
  # Two derivatives at a time: generating one reads a whole master and writes a new
  # file, so the bound here is the disks' rather than the scheduler's.
  queues: [integrity: 2, lifecycle: 1, ingest: 1, analysis: 2, presentation: 2],
  # Finished jobs are kept a week for inspection, then pruned. Nothing is known
  # only to a job: a failure a person must act on is a finding.
  pruner: [max_age: {7, :days}],
  # A node that stops while a job is running leaves that job executing for ever, and the
  # schedule below inserts at most one of each worker at a time — so one interrupted job
  # stops its whole stage, silently and permanently. Every restart of this deployment has
  # been leaving them: acquisition stopped dead for an hour after one, and analysis had
  # jobs stranded for three weeks.
  #
  # Half an hour, which is longer than any stage here takes on one item — the longest is
  # re-encoding a film — so a job this rescues is one nothing is working on.
  lifeline: [rescue_after: {30, :minutes}],
  cron: [
    crontab: [
      # spec-04 §3: each stage is scheduled work finding its own due items.
      {"* * * * *", Pluteus.Workers.AcquireFromInbox},
      {"* * * * *", Pluteus.Workers.IdentifyAcquisitions},
      {"* * * * *", Pluteus.Workers.PlaceAcquisitions},
      {"* * * * *", Pluteus.Workers.NormalizeHoldings},
      {"*/5 * * * *", Pluteus.Workers.ScheduleAnalysis},
      {"*/10 * * * *", Pluteus.Workers.ResolveCredits},
      {"30 4 * * *", Pluteus.Workers.FindStrayBytes},
      # spec-03 §5.2: verification is scheduled, not incidental.
      {"0 * * * *", Pluteus.Workers.ScheduleVerification},
      # [spec-10] §11.6: the derivative cache is bounded, and the bound is kept by a
      # pass that records having run.
      {"20 * * * *", Pluteus.Workers.EvictPresentationAssets},
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
    package: 90 * 86_400,
    software: 90 * 86_400,
    companion: 90 * 86_400
  }

# [spec-10] §11.6. The derivative cache's bound, which is capacity rather than
# vocabulary and so is configured here and not in §20's registry. Age and size both
# bound it: a library browsed daily never idles out, and one browsed once never
# reaches the ceiling. The period is what a run is called overdue against.
config :pluteus, Pluteus.Presentation,
  byte_ceiling: 5 * 1024 * 1024 * 1024,
  idle_seconds: 30 * 86_400,
  eviction_period_seconds: 3_600

# spec-04 §8. The deriving tools that run, and the wire schema versions a tool
# response may carry.
config :pluteus, Pluteus.Analysis,
  tools: [Pluteus.Analysis.Native, Pluteus.Analysis.Sidecar],
  schema_versions: [1]

# Beat tracking and constant-Q analysis of a long recording take a while; the
# timeout bounds one request, and a timeout is a transient failure.
config :pluteus, Pluteus.Analysis.Sidecar, url: "http://sidecar:8000", timeout_ms: 600_000

# spec-04 §6.4. Credits are resolved against MusicBrainz only with a contact
# for its User-Agent, which MusicBrainz requires. There is deliberately no
# default: a deployment sets one, or makes no request.
config :pluteus, Pluteus.Ingest.MusicBrainz, contact: nil

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

# spec-07 §8. A client key travels in the query string, where the Subsonic
# protocol puts it; it is kept out of the application's logs.
config :phoenix, :filter_parameters, ["password", "apiKey", "p", "t", "s"]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
