defmodule Pluteus.Workers.AnalyseInput do
  @moduledoc """
  Runs one tool over one input (spec-04 §8.3).

  A transient failure is retried with Oban's backoff a bounded number of times,
  and the last attempt's failure is recorded as a finding. A tool that has
  moved to another version since the job was queued is not run; the schedule
  queues the input again at the new version.
  """

  use Oban.Worker,
    queue: :analysis,
    max_attempts: 4,
    unique: [keys: [:tool, :version, :input_id], states: :incomplete, period: :infinity]

  alias Pluteus.Actor
  alias Pluteus.Analysis
  alias Pluteus.Principals

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}) do
    tool = String.to_existing_atom(args["tool"])

    with {:ok, %{version: version} = description} <- Analysis.describe(tool),
         true <- version == args["version"],
         %{} = input <- Analysis.input(args["input_id"]) do
      Actor.as(Principals.system!().id, fn ->
        run(tool, input, description, attempt, max_attempts)
      end)
    else
      false -> {:cancel, :tool_version_changed}
      nil -> {:cancel, :input_no_longer_analysable}
      {:error, _kind, reason} -> {:error, reason}
    end
  end

  defp run(tool, input, description, attempt, max_attempts) do
    case Analysis.analyse(tool, input, description) do
      {:error, :transient, reason} when attempt >= max_attempts ->
        Analysis.exhausted(description, input, reason)
        {:error, reason}

      {:error, :transient, reason} ->
        {:error, reason}

      _recorded ->
        :ok
    end
  end
end
