defmodule Pluteus.Workers.ApplyPositions do
  @moduledoc """
  One pass of spec-05 §7's apply stage for photographs: every resolved position writes the
  place it supports as its work's place of capture, and raises the finer one.
  """

  use Oban.Worker,
    queue: :matching,
    max_attempts: 1,
    unique: [states: :incomplete, period: :infinity]

  alias Pluteus.Ingest
  alias Pluteus.Matching.Geocoding

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    outcomes = Geocoding.apply_due()

    if Ingest.crashed?(outcomes), do: {:error, :items_crashed_see_findings}, else: :ok
  end
end
