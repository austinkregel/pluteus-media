defmodule Pluteus.ConsumptionFixtures do
  @moduledoc """
  A resume position as a session reports one.

  spec-01 §11.4 makes a position the property of a device, and [spec-10] §13.2
  weighs it against its category and the medium's whole extent — so even a test
  that only needs a position to exist needs a categorized work, a bound device and
  a recorded extent. This assembles the three.

  The extent is recorded on the work rather than on a manifestation, because these
  positions are reported against the work directly. Placement records it on the
  manifestation it carries (spec-04 §6.1); a test that needs that shape goes
  through ingest rather than through here.

  The default position sits well inside the film band of `continuity.json`: a film
  discards anything under two minutes as barely begun, so a test that wants a
  position to survive cannot use an arbitrary small number.
  """

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Addressing
  alias Pluteus.Events
  alias Pluteus.Ingest.Place
  alias Pluteus.Principals

  @extent 7_200_000
  @position 900_000

  @doc """
  A work of a category that keeps a position, and a device of the principal's to
  report it from. Returns what `Catalog.create_work/1` returns, plus `:device`.
  """
  @spec resumable_work!(Ecto.UUID.t(), String.t(), String.t()) :: map()
  def resumable_work!(principal_id, name \\ "The Long Goodbye", category \\ "film") do
    {:ok, catalogued} = Catalog.create_work(name)

    {:ok, _} =
      Catalog.categorize(catalogued.work.id, Place.category_scheme(), category, :automatic)

    {:ok, _} = Addressing.record_extent(catalogued.work.id, :millisecond, @extent)

    {:ok, device} = Principals.bind_device(principal_id, "a test device")

    Map.put(catalogued, :device, device)
  end

  @doc """
  Reports a position as a playing session would, and returns the row kept.

  `:playing`, `:sequence`, `:reported_at` and `:unit` are overridable, which is
  what §13.3's conflict cases need. The extent is not: §13.2 reads it from the
  catalog, so a test that needs a different one records it there.
  """
  @spec position!(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t(), non_neg_integer(), keyword()) ::
          Events.ResumePosition.t()
  def position!(principal_id, res_id, device_id, position \\ @position, opts \\ []) do
    {:ok, kept} = report(principal_id, res_id, device_id, position, opts)

    kept
  end

  @doc """
  Reports a position and answers whatever §13.2 decided, so a test can assert a
  discard as readily as a keep.
  """
  @spec report(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t(), non_neg_integer(), keyword()) ::
          {:ok, Events.ResumePosition.t()} | {:discarded, atom()}
  def report(principal_id, res_id, device_id, position, opts \\ []) do
    Events.report_position(%{
      principal_id: principal_id,
      res_id: res_id,
      device_id: device_id,
      position: position,
      unit: Keyword.get(opts, :unit, :millisecond),
      reported_at: Keyword.get(opts, :reported_at, DateTime.utc_now()),
      sequence: Keyword.get(opts, :sequence, 1),
      playing: Keyword.get(opts, :playing, true)
    })
  end

  @doc """
  The extent and position the defaults use, for a test that needs to reason about
  them.
  """
  @spec extent() :: non_neg_integer()
  def extent, do: @extent

  @spec position() :: non_neg_integer()
  def position, do: @position
end
