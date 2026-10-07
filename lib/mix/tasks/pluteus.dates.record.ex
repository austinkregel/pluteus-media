defmodule Mix.Tasks.Pluteus.Dates.Record do
  @shortdoc "Records the date each placed holding's container states"

  @moduledoc """
  Reads the issue date of every holding already in the catalogue.

  Placement reads a container's date as it carries the holding, so holdings placed before
  it read one carry no date and nothing browsing by date can find them. This reads them
  now, through placement's own path, so what it records is what placement would have.

  Running it again records nothing new: a holding already related to the time-span its
  date names is left as it is, so this can be run after any ingest without reasoning about
  which holdings it has already seen.

  A holding whose container states no date it can read is left alone and counted, because
  that is a holding whose date is unexamined rather than one this missed.
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
      |> Enum.map(&Place.record_date/1)
      |> Enum.frequencies()

    recorded = Map.get(outcomes, :recorded, 0)
    stated_none = Map.get(outcomes, :states_none, 0)

    Mix.shell().info("""
    #{recorded + stated_none} placed holdings read.
      #{recorded} state a date, and now carry it.
      #{stated_none} state none their form fixes, and carry none.
    """)
  end
end
