defmodule Pluteus.Presentation.Eviction do
  @moduledoc """
  Keeping the derivative cache within a bound ([spec-10] §11.6).

  Every presentation asset is evictable under a bounded policy, and the bound is two
  things at once: an artefact nobody has asked for in the idle period goes because it
  is not being used, and beyond the byte ceiling the least recently served go until the
  cache is under it again. The first bounds age, the second bounds size, and a cache
  needs both — a library browsed every day would never idle out, and one browsed once
  would never reach the ceiling.

  **Nothing is exempt, including the profiles §20 generates at ingest.** That is what
  makes the bound safe rather than nearly safe: an exemption is an unbounded set, and
  the at-ingest profiles return on the next pass over the holdings that need them. A
  cache whose floor cannot be evicted is a disk with a slow leak.

  Eviction never touches a holding. Everything here is regenerable from the master it
  names, which is the whole reason spec-01 §13.7 keeps it out of the backup.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Ingest
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Asset
  alias Pluteus.Presentation.EvictionRun
  alias Pluteus.Repo

  @doc """
  Runs one pass, and records that it ran.

  Answers what it did, which is also what the run row carries.
  """
  @spec run(DateTime.t()) :: %{
          considered: non_neg_integer(),
          evicted: non_neg_integer(),
          bytes_reclaimed: non_neg_integer()
        }
  def run(now \\ DateTime.utc_now()) do
    {:ok, started} = Repo.insert(EvictionRun.started_changeset(%{started_at: now}))

    held = by_least_recently_served()
    going = choose(held, now)

    for asset <- going, do: Presentation.discard(asset)

    counted = %{
      considered: length(held),
      evicted: length(going),
      bytes_reclaimed: Enum.sum(Enum.map(going, & &1.size))
    }

    {:ok, _finished} =
      started
      |> EvictionRun.finished_changeset(Map.put(counted, :finished_at, DateTime.utc_now()))
      |> Repo.update()

    counted
  end

  @doc """
  Whether a pass has failed to complete within twice its period.

  A run that started and never finished is a crash, and one that has not started
  within the window is a timer that has stopped. §11.6 asks that the eviction be
  observable as having run, so not having run is the thing to notice.
  """
  @spec overdue?(DateTime.t()) :: boolean()
  def overdue?(now \\ DateTime.utc_now()) do
    window = 2 * period_seconds()

    case Repo.one(from r in EvictionRun, order_by: [desc: r.started_at], limit: 1) do
      nil -> false
      %EvictionRun{finished_at: nil} = run -> DateTime.diff(now, run.started_at) > window
      %EvictionRun{finished_at: finished_at} -> DateTime.diff(now, finished_at) > window
    end
  end

  @doc """
  Records a finding where a pass is overdue, so that a stopped timer reaches a person.
  """
  @spec report_if_overdue(DateTime.t()) :: :ok
  def report_if_overdue(now \\ DateTime.utc_now()) do
    if overdue?(now) do
      Ingest.record_finding(%{
        stage: :normalize,
        kind: "presentation_eviction_overdue",
        permanent: false,
        detail: %{window_seconds: 2 * period_seconds()},
        location: "presentation/"
      })
    end

    :ok
  end

  # Idle first, then as many of the rest as the ceiling requires. The idle ones are
  # counted against the ceiling too, so a pass that clears enough by age stops there.
  defp choose(held, now) do
    {idle, fresh} = Enum.split_with(held, &idle?(&1, now))

    remaining = Enum.sum(Enum.map(fresh, & &1.size))

    idle ++ over_ceiling(fresh, remaining)
  end

  # `held` arrives least recently served first, which is the order §11.6 evicts in.
  defp over_ceiling(_fresh, remaining) when remaining <= 0, do: []

  defp over_ceiling(fresh, remaining) do
    ceiling = byte_ceiling()

    {going, _left} =
      Enum.reduce(fresh, {[], remaining}, fn asset, {going, total} ->
        if total > ceiling, do: {[asset | going], total - asset.size}, else: {going, total}
      end)

    Enum.reverse(going)
  end

  defp idle?(%Asset{last_served_at: last_served_at}, now),
    do: DateTime.diff(now, last_served_at, :second) > idle_seconds()

  defp by_least_recently_served do
    Repo.all(from p in Asset, order_by: [asc: p.last_served_at, asc: p.subject_id])
  end

  defp byte_ceiling, do: config(:byte_ceiling)
  defp idle_seconds, do: config(:idle_seconds)
  defp period_seconds, do: config(:eviction_period_seconds)

  defp config(key), do: :pluteus |> Application.fetch_env!(Presentation) |> Keyword.fetch!(key)
end
