defmodule Pluteus.Workers.ApplyMusic do
  @moduledoc """
  One pass of spec-05 §7's apply stage for music: every resolved MusicBrainz match record
  has the identifiers its answer holds written, and the equations they license performed.
  """

  use Oban.Worker,
    queue: :matching,
    max_attempts: 1,
    unique: [states: :incomplete, period: :infinity]

  alias Pluteus.Ingest
  alias Pluteus.Matching.Music

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    outcomes = Music.apply_due()

    if Ingest.crashed?(outcomes), do: {:error, :items_crashed_see_findings}, else: :ok
  end
end
