defmodule Pluteus.Jobs.Repo do
  @moduledoc """
  The queue's own database.

  Oban's tables and nothing else. They are not the catalogue: nothing joins them to it,
  no trigger on them records a catalog write, and `Pluteus.Backup` classifies everything
  here as excluded because the queue is operational state the schedule rebuilds — which
  spec-04 §3 makes true by giving every stage its own way of finding what it is due to do.

  Separate because the queue polls. It fetches, elects a leader and prunes whether or not
  anything is happening, so on one server that work shares a connection pool, shared
  buffers and autovacuum with the request a person is waiting on.

  ## It logs nothing

  `log: false` is configured for this repo, and it is the point rather than tidiness. The
  development log is the only window onto a running server, and a queue polling several
  times a second fills it with its own bookkeeping — so a question about what a page did
  becomes a search through what the queue was doing meanwhile. What the queue is doing is
  asked of the queue.

  ## Its migrations are its own

  `:priv` is configured, not given here, because that is where `mix ecto.migrate` reads
  it: `Mix.EctoSQL.source_repo_priv/1` takes `repo.config()[:priv]` and otherwise defaults
  to `priv/` plus the last segment of the module name — which for this one is `repo`, the
  catalogue's own directory. Given here instead it is silently ignored and this database
  is handed the catalogue's seventy-odd migrations, which is what happened once.

  Both repos are named in `ecto_repos`, and every ecto task walks that list.
  """
  use Ecto.Repo,
    otp_app: :pluteus,
    adapter: Ecto.Adapters.Postgres
end
