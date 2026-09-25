defmodule Pluteus.Workers.EvictPresentationAssets do
  @moduledoc """
  Runs one pass of the eviction policy ([spec-10] §11.6).

  It checks for an overdue pass before running, so that a timer which stopped is
  reported by the pass that notices rather than by nobody. A pass that crashes leaves
  its run row unfinished, which is what the next pass reads.
  """

  use Oban.Worker, queue: :presentation, max_attempts: 1

  alias Pluteus.Presentation.Eviction

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    :ok = Eviction.report_if_overdue()
    _counted = Eviction.run()

    :ok
  end
end
