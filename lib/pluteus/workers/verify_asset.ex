defmodule Pluteus.Workers.VerifyAsset do
  @moduledoc """
  Checks one asset's bytes against its recorded digest.

  One job per asset, and at most one waiting or running per asset at a time, so
  an hourly scheduling pass that finds a large library still due does not queue
  it twice. A single attempt: the outcome of a check is recorded whatever it is,
  and a check that could not run is itself surfaced rather than retried until it
  happens to succeed.

  The check is the deployment's own work, and what it records against the asset
  is attributed to the System principal (spec-06 §6.2). Nothing sets an actor
  for a job the queue runs, so this sets its own.
  """

  use Oban.Worker,
    queue: :integrity,
    max_attempts: 1,
    unique: [keys: [:asset_id], states: :incomplete, period: :infinity]

  alias Pluteus.Actor
  alias Pluteus.Assets
  alias Pluteus.Lifecycle
  alias Pluteus.Principals

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"asset_id" => asset_id}}) do
    case Lifecycle.state(asset_id) do
      {:purged, _res, _tombstone} ->
        {:cancel, :purged_before_verification}

      _present ->
        {:ok, _changes} = Actor.as(Principals.system!().id, fn -> Assets.verify(asset_id) end)
        :ok
    end
  end
end
