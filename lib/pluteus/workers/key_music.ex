defmodule Pluteus.Workers.KeyMusic do
  @moduledoc """
  One pass of spec-05 §7's key stage for music: every placed track, and every release
  ripped to one file, some scheme of which has no current MusicBrainz match record has the
  identifiers it carries read and recorded.
  """

  use Oban.Worker,
    queue: :matching,
    max_attempts: 1,
    unique: [states: :incomplete, period: :infinity]

  alias Pluteus.Ingest
  alias Pluteus.Matching.Music

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    outcomes = Music.key_due()

    if Ingest.crashed?(outcomes), do: {:error, :items_crashed_see_findings}, else: :ok
  end
end
