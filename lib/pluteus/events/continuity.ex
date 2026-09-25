defmodule Pluteus.Events.Continuity do
  @moduledoc """
  Which of the positions a principal holds for one res a surface shows
  ([spec-10] §13.3).

  Two devices reporting different positions for one principal and one res is the
  ordinary case. Reports fall into two tiers:

  - A session that was playing and is still reporting speaks for the present.
  - A paused session, and a playing session gone quiet beyond the reporting
    interval, speak only for the past.

  Every report in the first tier outranks every report in the second. Within a
  tier the greatest `{reported_at, sequence}` wins; the sequence separates two
  reports of one session that share a reporting time.

  A report is ranked by the time it was made, so one flushed from an offline queue
  carries the time and sequence it was made with and is weighed against its
  contemporaries rather than against the moment it arrived.

  Nothing here reads the database, so the rule can be exercised over reports built
  in a test rather than over rows.
  """

  alias Pluteus.Continuity.Registry
  alias Pluteus.Events.ResumePosition

  @typedoc """
  A position as §13.3 weighs it.
  """
  @type report :: %{
          required(:playing) => boolean(),
          required(:reported_at) => DateTime.t(),
          required(:sequence) => non_neg_integer(),
          optional(any()) => any()
        }

  @doc """
  The position a surface shows, or nil where there are none.

  `now` is when the question is asked, which the idle rule is measured against.
  """
  @spec winner([report()], DateTime.t()) :: report() | nil
  def winner([], _now), do: nil
  def winner(positions, now), do: Enum.max_by(positions, &rank(&1, now))

  @doc """
  Whether a report has stopped speaking for the present.

  Only a playing session can: a paused one was never claiming to be where the
  person is now, so it has nothing to go stale.
  """
  @spec idle?(report(), DateTime.t()) :: boolean()
  def idle?(%{playing: false}, _now), do: false

  def idle?(%{playing: true, reported_at: reported_at}, now) do
    DateTime.diff(now, reported_at, :millisecond) > Registry.reporting_interval_ms()
  end

  @doc """
  How far a resume would move a position backwards, in the position's own unit,
  and whether that exceeds what §13.3 lets a surface do silently.
  """
  @spec backwards(ResumePosition.t(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:stated, non_neg_integer()}
  def backwards(%ResumePosition{position: held, unit: unit}, resuming_at) do
    moved = max(held - resuming_at, 0)

    if moved > Registry.backwards_threshold(unit) do
      {:stated, moved}
    else
      {:ok, moved}
    end
  end

  # Greater sorts first. The tier leads, then the reporting time, then the sequence
  # for a tie inside one microsecond, then the device so that two devices reporting
  # identically still answer the same way on every call.
  #
  # The time is a plain integer because a `%DateTime{}` in a tuple is compared in
  # Erlang term order, which walks a struct's keys alphabetically and so weighs the
  # day before the year.
  defp rank(%{reported_at: reported_at, sequence: sequence} = report, now) do
    speaking_for_now = report.playing and not idle?(report, now)

    {
      if(speaking_for_now, do: 1, else: 0),
      DateTime.to_unix(reported_at, :microsecond),
      sequence,
      Map.get(report, :device_id)
    }
  end
end
