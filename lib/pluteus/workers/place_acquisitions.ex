defmodule Pluteus.Workers.PlaceAcquisitions do
  @moduledoc """
  One pass of the place stage over every identified acquisition whose inbox
  directory has settled (spec-04 §6).
  """

  use Oban.Worker,
    queue: :ingest,
    max_attempts: 1,
    unique: [states: :incomplete, period: :infinity]

  alias Pluteus.Ingest
  alias Pluteus.Ingest.Place

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    outcomes = Place.place_due(Ingest.inbox())

    if Ingest.crashed?(outcomes), do: {:error, :items_crashed_see_findings}, else: :ok
  end
end
