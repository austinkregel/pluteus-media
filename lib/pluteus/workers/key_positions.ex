defmodule Pluteus.Workers.KeyPositions do
  @moduledoc """
  One pass of spec-05 §7's key stage for photographs: every placed image whose work has
  no current GeoNames match record has its EXIF position read and recorded.
  """

  use Oban.Worker,
    queue: :matching,
    max_attempts: 1,
    unique: [states: :incomplete, period: :infinity]

  alias Pluteus.Ingest
  alias Pluteus.Matching.Geocoding

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    outcomes = Geocoding.key_due()

    if Ingest.crashed?(outcomes), do: {:error, :items_crashed_see_findings}, else: :ok
  end
end
