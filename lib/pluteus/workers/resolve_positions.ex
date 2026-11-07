defmodule Pluteus.Workers.ResolvePositions do
  @moduledoc """
  One pass of spec-05 §7's resolve stage for photographs: every keyed position is
  answered from the GeoNames snapshot the household holds, and every answer from an older
  snapshot is made due again.
  """

  use Oban.Worker,
    queue: :matching,
    max_attempts: 1,
    unique: [states: :incomplete, period: :infinity]

  alias Pluteus.Ingest
  alias Pluteus.Matching.Geocoding

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    outcomes = Geocoding.resolve_due()

    if Ingest.crashed?(outcomes), do: {:error, :items_crashed_see_findings}, else: :ok
  end
end
