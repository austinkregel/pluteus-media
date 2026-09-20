defmodule Pluteus.Workers.ResolveCredits do
  @moduledoc """
  One pass of the credit-resolving stage (spec-04 §6.4).

  Every credit that names no artist is given one first, which asks nothing of
  anyone. A deployment configured with no MusicBrainz contact then makes no
  request, and the job is cancelled saying so: its artists stay artists until
  something says which kind of agent they are.
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
