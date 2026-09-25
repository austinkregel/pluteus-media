defmodule Pluteus.Workers.NormalizeHoldings do
  @moduledoc """
  One pass of the normalize stage over every placed holding that has no master,
  or whose master is not in its class's standard format (spec-04 §7).

  A holding that gained a master is the first moment a derivative can be made of it,
  so [spec-10] §11.6's at-ingest profiles are queued from here rather than from
  placement: generation reads the Normalized master, which placement has not yet
  established.
  """

  use Oban.Worker,
    queue: :ingest,
    max_attempts: 1,
    unique: [states: :incomplete, period: :infinity]

  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Repo
  alias Pluteus.Workers.GeneratePresentationAsset

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    outcomes = Normalize.normalize_due()

    for {digital_item_id, _outcome} <- outcomes, subject = subject_of(digital_item_id), subject do
      GeneratePresentationAsset.queue_at_ingest(subject)
    end

    if Ingest.crashed?(outcomes),
      do: {:error, :items_crashed_see_findings},
      else: :ok
  end

  # The manifestation, because that is what a surface asks about and what a profile's
  # applicability is decided from.
  defp subject_of(digital_item_id) do
    case Repo.get(DigitalItem, digital_item_id) do
      nil -> nil
      %DigitalItem{manifestation_id: manifestation_id} -> manifestation_id
    end
  end
end
