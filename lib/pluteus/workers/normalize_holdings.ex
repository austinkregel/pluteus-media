defmodule Pluteus.Workers.NormalizeHoldings do
  @moduledoc """
  One pass of the normalize stage over every placed holding that has no master,
  or whose master is not in its class's standard format (spec-04 §7).
  """

  use Oban.Worker,
    queue: :ingest,
    max_attempts: 1,
    unique: [states: :incomplete, period: :infinity]

  alias Pluteus.Ingest.Normalize

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Normalize.normalize_due()
    :ok
  end
end
