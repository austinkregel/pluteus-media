defmodule Pluteus.Events.ContinuityTest do
  @moduledoc """
  [spec-10] §13.3's conflict rule and §13.2's thresholds. Both are pure, so these
  exercise them over reports built here rather than over rows.

  Asserts spec-10 criteria 31 and 32.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Continuity.Registry
  alias Pluteus.Events.Continuity
  alias Pluteus.Events.Thresholds

  @now ~U[2026-09-29 12:00:00.000000Z]

  defp report(opts) do
    %{
      device_id: opts[:device] || "device-a",
      position: opts[:position] || 100,
      playing: Keyword.get(opts, :playing, true),
      reported_at: DateTime.add(@now, -(opts[:ago] || 0), :millisecond),
      sequence: opts[:sequence] || 1
    }
  end

  describe "32. Of two live reports for one principal, res and device, the playing one wins" do
    test "a playing session beats a paused one that reported later" do
      playing = report(device: "television", ago: 5_000, playing: true)
      paused = report(device: "phone", ago: 0, playing: false)

      # A paused session's position is a statement about the past; a playing
      # session's is a statement about the present.
      assert Continuity.winner([paused, playing], @now).device_id == "television"
    end

    test "between two playing sessions the more recent one wins" do
      older = report(device: "phone", ago: 8_000)
      newer = report(device: "television", ago: 1_000)

      assert Continuity.winner([older, newer], @now).device_id == "television"
    end

    test "the sequence breaks a tie between two reports sharing a reporting time" do
      first = report(device: "phone", ago: 0, sequence: 4)
      second = report(device: "phone", ago: 0, sequence: 9)

      assert Continuity.winner([first, second], @now).sequence == 9
    end

    test "a live report from a session idle beyond the reporting interval is ignored" do
      quiet =
        report(device: "television", ago: Registry.reporting_interval_ms() * 3, playing: true)

      paused = report(device: "phone", ago: 1_000, playing: false)

      assert Continuity.idle?(quiet, @now)
      refute Continuity.idle?(paused, @now)

      # A session that has stopped reporting has stopped speaking for the present,
      # so it no longer outranks a paused report.
      assert Continuity.winner([quiet, paused], @now).device_id == "phone"
    end

    test "being ignored demotes a report rather than erasing the position" do
      quiet =
        report(device: "television", ago: Registry.reporting_interval_ms() * 3, playing: true)

      # The only report a res has still answers, at its own age.
      assert Continuity.winner([quiet], @now).device_id == "television"
    end

    test "a report that kept its original time is ordered by it, not discarded for it" do
      # This is what a flush from a declared offline queue looks like: a report
      # made long ago, arriving now. Nothing discards it for being old.
      flushed = report(device: "phone", ago: 600_000, playing: true, position: 500)

      assert Continuity.winner([flushed], @now).position == 500
    end

    test "furthest-position-wins does not hold" do
      # An accidental scrub to the end would otherwise be unrecoverable.
      near_the_end = report(device: "phone", ago: 9_000, position: 9_000_000, playing: false)
      where_they_are = report(device: "television", ago: 0, position: 120_000, playing: true)

      assert Continuity.winner([near_the_end, where_they_are], @now).position == 120_000
    end

    test "last-writer-wins alone does not hold" do
      playing = report(device: "television", ago: 4_000, playing: true)
      paused_later = report(device: "phone", ago: 0, playing: false)

      assert Continuity.winner([paused_later, playing], @now).device_id == "television"
    end

    test "the answer does not depend on the order the reports arrive in" do
      reports = [
        report(device: "a", ago: 3_000, playing: true),
        report(device: "b", ago: 0, playing: false),
        report(device: "c", ago: 30_000, playing: true)
      ]

      chosen = Continuity.winner(reports, @now).device_id

      for permutation <- permutations(reports) do
        assert Continuity.winner(permutation, @now).device_id == chosen
      end
    end

    test "no reports means no position" do
      assert is_nil(Continuity.winner([], @now))
    end
  end

  describe "31. A position below the floor or above the ceiling for its category is discarded" do
    test "an absolute category discards the first couple of minutes of a film" do
      assert Thresholds.weigh("film", 60_000, 7_200_000) == :below_floor
      assert Thresholds.weigh("film", 600_000, 7_200_000) == :keep
    end

    test "an absolute ceiling is the extent remaining, not a proportion of it" do
      # Three minutes of credits left is the fact; nine minutes, which is five per
      # cent of a three-hour film, is not.
      assert Thresholds.weigh("film", 7_100_000, 7_200_000) == :consumed
      assert Thresholds.weigh("film", 6_900_000, 7_200_000) == :keep
    end

    test "a proportional category measures both ends against the whole" do
      assert Thresholds.weigh("music_recording", 10_000, 900_000) == :below_floor
      assert Thresholds.weigh("music_recording", 450_000, 900_000) == :keep
      assert Thresholds.weigh("music_recording", 890_000, 900_000) == :consumed
    end

    test "a res below the minimum length carries no position" do
      assert Thresholds.weigh("film", 300_000, 400_000) == :too_short
      assert Thresholds.weigh("music_recording", 100_000, 200_000) == :too_short
    end

    test "a category that is looked at rather than resumed keeps none" do
      assert Thresholds.weigh("photograph", 1, 1) == :keeps_none
      assert Thresholds.weigh("video_game", 1, 1) == :keeps_none
    end

    test "a page-counted category is weighed in pages" do
      assert Thresholds.weigh("comic_issue", 1, 40) == :below_floor
      assert Thresholds.weigh("comic_issue", 20, 40) == :keep
      assert Thresholds.weigh("comic_issue", 39, 40) == :consumed
      assert Thresholds.weigh("comic_issue", 2, 4) == :too_short
    end

    test "an extent nobody recorded keeps nothing rather than being treated as long enough" do
      # §8.4's figure is recorded where a probe reads one and left where it does not, so
      # a holding without one is a state the catalog admits. Both the floor and the
      # ceiling are measured against it, so the report is discarded and said to be rather
      # than kept against a length nobody knows.
      assert Thresholds.weigh("film", 600_000, nil) == :unmeasured
      assert Thresholds.weigh("comic_issue", 20, nil) == :unmeasured
    end

    test "a category that keeps no position needs no measurement to say so" do
      assert Thresholds.weigh("photograph", 1, nil) == :keeps_none
    end

    test "a category the registry does not name raises" do
      assert_raise KeyError, fn -> Thresholds.weigh("hologram", 1, 2) end
    end
  end

  describe "how far a resume may move backwards before it is stated" do
    test "a small move back is silent and a large one is stated" do
      held = %Pluteus.Events.ResumePosition{position: 600_000, unit: :millisecond}

      assert {:ok, 10_000} = Continuity.backwards(held, 590_000)
      assert {:stated, 300_000} = Continuity.backwards(held, 300_000)
    end

    test "moving forwards is no move backwards at all" do
      held = %Pluteus.Events.ResumePosition{position: 600_000, unit: :millisecond}

      assert {:ok, 0} = Continuity.backwards(held, 900_000)
    end

    test "the threshold is per unit, because the rule applies to pages too" do
      held = %Pluteus.Events.ResumePosition{position: 40, unit: :page}

      assert {:ok, 2} = Continuity.backwards(held, 38)
      assert {:stated, 30} = Continuity.backwards(held, 10)
    end
  end

  defp permutations([]), do: [[]]

  defp permutations(list) do
    for element <- list, rest <- permutations(list -- [element]), do: [element | rest]
  end
end
