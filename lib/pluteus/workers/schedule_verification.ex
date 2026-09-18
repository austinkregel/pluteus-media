defmodule Pluteus.Workers.ScheduleVerification do
  @moduledoc """
  Queues a verification for every asset not currently known to be intact.

  spec-03 §5.2 requires verification to be a scheduled operation rather than an
  operator convention or a side effect of playback. This is the schedule; the
  checks themselves run one asset per job, bounded by the integrity queue.
  """

  use Oban.Worker, queue: :integrity, max_attempts: 1

  alias Pluteus.Assets
  alias Pluteus.Workers.VerifyAsset

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Enum.each(Assets.unverified(), fn asset ->
      {:ok, _job} = Oban.insert(VerifyAsset.new(%{asset_id: asset.id}))
    end)
  end
end
