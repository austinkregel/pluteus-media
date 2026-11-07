defmodule Pluteus.Workers.ResolveMusic do
  @moduledoc """
  One pass of spec-05 §7's resolve stage for music: every keyed MusicBrainz match record is
  answered from the snapshot the household holds.
  """

  use Oban.Worker,
    queue: :matching,
    max_attempts: 1,
    unique: [states: :incomplete, period: :infinity]

  alias Pluteus.Ingest
  alias Pluteus.Matching.Music

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    outcomes = Music.resolve_due()

    if Ingest.crashed?(outcomes), do: {:error, :items_crashed_see_findings}, else: :ok
  end
end
