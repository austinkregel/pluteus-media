defmodule Pluteus.Workers.ResolveCredits do
  @moduledoc """
  One pass of the credit-resolving stage (spec-04 §6.4).

  A deployment configured with no MusicBrainz contact makes no request; the job
  is cancelled saying so, and the credits stay names.
  """

  use Oban.Worker,
    queue: :ingest,
    max_attempts: 1,
    unique: [states: :incomplete, period: :infinity]

  alias Pluteus.Ingest.Credits

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Credits.resolve_due() do
      {:ok, _looked_up} -> :ok
      {:error, :no_contact_configured} -> {:cancel, :no_musicbrainz_contact_configured}
    end
  end
end
