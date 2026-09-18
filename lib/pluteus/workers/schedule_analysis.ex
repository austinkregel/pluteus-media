defmodule Pluteus.Workers.ScheduleAnalysis do
  @moduledoc """
  Asks each tool what it is and queues one analysis per due input
  (spec-04 §8.4).

  A tool that cannot describe itself is not scheduled; the others are, and the
  job then fails naming the tool, so the outage is on record.
  """

  use Oban.Worker,
    queue: :analysis,
    max_attempts: 1,
    unique: [states: :incomplete, period: :infinity]

  alias Pluteus.Analysis
  alias Pluteus.Workers.AnalyseInput

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    unavailable =
      Enum.flat_map(Analysis.tools(), fn tool ->
        case Analysis.describe(tool) do
          {:ok, description} ->
            schedule(tool, description)
            []

          {:error, _kind, reason} ->
            [{tool, reason}]
        end
      end)

    if unavailable == [], do: :ok, else: {:error, {:tools_unavailable, unavailable}}
  end

  defp schedule(tool, %{name: name, version: version}) do
    for input <- Analysis.due(name, version) do
      {:ok, _job} =
        %{tool: Atom.to_string(tool), version: version, input_id: input.input_id}
        |> AnalyseInput.new()
        |> Oban.insert()
    end
  end
end
