defmodule Mix.Tasks.Pluteus.Probes.Record do
  @shortdoc "Records every placed holding's probe against the bytes it read"

  @moduledoc """
  Puts each placed holding's probe where a surface looks for it.

  spec-04 §6.1 makes a derivation's input the res whose bytes it read, which for a probe
  is the asset. A holding placed before that was so carries its reading against the
  manifestation instead: a true reading that nothing asks about, so [spec-10] §11.2's
  box is reserved at §20's assumed shape for the category rather than at the holding's
  own, and a grid of photographs is drawn as though every one of them were the same
  shape.

  This reads the probe already on each acquisition, through placement's own path. A
  holding already recorded is left as it is, so it can be run after any ingest.
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
      |> Enum.map(&Place.record_probe!/1)
      |> Enum.frequencies()

    recorded = Map.get(outcomes, :recorded, 0)
    already = Map.get(outcomes, :recorded_already, 0)
    stated_none = Map.get(outcomes, :states_none, 0)

    Mix.shell().info("""
    #{recorded + already + stated_none} placed holdings read.
      #{recorded} had no reading against their bytes, and now have.
      #{already} were recorded already.
      #{stated_none} carry no probe, and nothing was read from them.
    """)
  end
end
