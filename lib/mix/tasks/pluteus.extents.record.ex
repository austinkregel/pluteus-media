defmodule Mix.Tasks.Pluteus.Extents.Record do
  @shortdoc "Records how much there is of every placed holding"

  @moduledoc """
  Measures every holding already in the catalogue.

  Placement measures a holding as it carries it, so one placed before it did carries no
  figure — and spec-01 §8.4's figure is what every address within a holding is placed
  against and what [spec-10] §13.2's thresholds are measured against.

  This reads the probe already on each acquisition, through placement's own path. A
  holding already measured is left as it is, so it can be run after any ingest.
  """

  use Mix.Task

  import Ecto.Query

  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Ingest.Place
  alias Pluteus.Repo

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    outcomes =
      from(a in Acquisition, where: a.state == :placed, order_by: a.id)
      |> Repo.all()
      |> Enum.map(&Place.record_extent/1)
      |> Enum.frequencies()

    recorded = Map.get(outcomes, :recorded, 0)
    already = Map.get(outcomes, :measured_already, 0)
    stated_none = Map.get(outcomes, :states_none, 0)

    Mix.shell().info("""
    #{recorded + already + stated_none} placed holdings read.
      #{recorded} were not measured, and now are.
      #{already} were measured already.
      #{stated_none} state no length their probe read, and carry none.
    """)
  end
end
