defmodule Pluteus.Corpus.Repo do
  @moduledoc """
  The corpora's own database (spec-05 §5.5, §5.7).

  What it holds is published data the household keeps a copy of, so that a lookup answers
  without telling anybody it was asked: each corpus in a schema of its own, and the record
  of which snapshot of each is held. None of it is the household's, and `Pluteus.Backup`
  classifies all of it as excluded because every corpus is refetched after loss. The
  match records drawn from a corpus are the household's own and live in the catalogue's
  database, where they are backed up.

  Separate because a corpus is imported in bulk — millions of rows at a time — and an
  import on the catalogue's server would take its buffers and its disk from the request a
  person is waiting on. It logs nothing for the reason the queue's database does not.

  `:priv` is configured rather than given here, for the reason `Pluteus.Jobs.Repo` gives.
  """
  use Ecto.Repo,
    otp_app: :pluteus,
    adapter: Ecto.Adapters.Postgres
end
