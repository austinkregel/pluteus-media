defmodule Pluteus.Workers.AnalyseInput do
  @moduledoc """
  Runs one tool over one input (spec-04 §8.3).

  The tool runs outside any transaction, however long it takes; only recording
  what it measured writes. A transient failure is retried with Oban's backoff a
  bounded number of times, and the last attempt's failure is recorded as a
  finding. So is an exception on the last attempt, which is then raised again
  for Oban to record too. A tool that has moved to another version since the
  job was queued is not run; the schedule queues the input again at the new
  version.
  """

  use Oban.Worker,
    queue: :analysis,
    max_attempts: 4,
    unique: [keys: [:tool, :version, :input_id], states: :incomplete, period: :infinity]

  alias Pluteus.Analysis

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}) do
    tool = String.to_existing_atom(args["tool"])

    with {:ok, %{version: version} = description} <- Analysis.describe(tool),
         true <- version == args["version"],
         %{} = input <- Analysis.input(args["input_id"]) do
      guard(attempt >= max_attempts, description, input, fn ->
        run(tool, input, description, attempt, max_attempts)
      end)
    else
      false -> {:cancel, :tool_version_changed}
      nil -> {:cancel, :input_no_longer_analysable}
      {:error, _kind, reason} -> {:error, reason}
    end
  end

  defp guard(false, _description, _input, fun), do: fun.()

  defp guard(true, description, input, fun) do
    fun.()
  rescue
    exception ->
      Analysis.crashed(description, input, Exception.format(:error, exception, __STACKTRACE__))
      reraise exception, __STACKTRACE__
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
