defmodule Pluteus.Workers.GeneratePresentationAsset do
  @moduledoc """
  Generates one derivative for one subject ([spec-10] §11.6).

  **The job's uniqueness is the "generating" state.** `Pluteus.Presentation.Asset`
  carries no state column, and this is why it needs none: a surface asking twice for
  an artefact that is not there queues one job, and the second request finds the
  first still incomplete. The unique key is the subject and the profile, which is what
  identifies the artefact, so two surfaces asking at once do not encode twice.

  A refusal cancels rather than retrying. Nothing about a profile that does not apply,
  or a subject with no master, changes on a second attempt, and Oban's backoff would
  turn a request that should never have been made into a queue of them.
  """

  use Oban.Worker,
    queue: :presentation,
    max_attempts: 3,
    unique: [keys: [:subject_id, :profile], states: :incomplete, period: :infinity]

  alias Pluteus.Presentation.Generate
  alias Pluteus.Presentation.Registry

  @doc """
  Queues generation of one artefact, if it is not already queued.
  """
  @spec queue(Ecto.UUID.t(), String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def queue(subject_id, profile) do
    %{subject_id: subject_id, profile: profile}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Queues the profiles §20 generates at ingest for a subject that has just been placed.

  §11.6 permits generating an artefact at ingest where it is cheap and universally
  needed, and names those in the registry rather than here. A profile that does not
  apply to the subject is queued and cancels itself, which keeps the decision about
  what applies in one place instead of two that could disagree.
  """
  @spec queue_at_ingest(Ecto.UUID.t()) :: [String.t()]
  def queue_at_ingest(subject_id) do
    for profile <- Registry.generated_at_ingest(),
        {:ok, _job} = queue(subject_id, profile) do
      profile
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subject_id" => subject_id, "profile" => profile}}) do
    case Generate.run(subject_id, profile) do
      {:ok, _asset} -> :ok
      {:refused, reason} -> {:cancel, reason}
      {:error, kind, _detail} -> {:error, kind}
    end
  end
end
