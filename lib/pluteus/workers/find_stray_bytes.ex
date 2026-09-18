defmodule Pluteus.Workers.FindStrayBytes do
  @moduledoc """
  Records a finding for bytes under primary storage that no record accounts for
  (spec-04 §4.3). It reads the whole of primary storage, so it runs daily.
  """

  use Oban.Worker,
    queue: :ingest,
    max_attempts: 1,
    unique: [states: :incomplete, period: :infinity]

  alias Pluteus.Ingest

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Ingest.find_stray_bytes()
    :ok
  end
end
