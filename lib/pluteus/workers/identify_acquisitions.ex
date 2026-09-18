defmodule Pluteus.Workers.IdentifyAcquisitions do
  @moduledoc """
  One pass of the identify stage over every stored acquisition not yet
  identified and with no uncleared finding (spec-04 §5).

  Acquisition identifies what it moves as it moves it. This pass completes what
  an interruption left, and retries what a person has cleared.
  """

  use Oban.Worker,
    queue: :ingest,
    max_attempts: 1,
    unique: [states: :incomplete, period: :infinity]

  alias Pluteus.Ingest

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Ingest.identify_due()
    :ok
  end
end
