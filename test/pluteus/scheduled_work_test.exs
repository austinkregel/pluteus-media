defmodule Pluteus.ScheduledWorkTest do
  @moduledoc """
  What a scheduled pass costs to find its own work.

  spec-04 §3 makes each stage scheduled work that finds its due items from recorded state,
  and spec-04 §8's analysis is scheduled the same way. A pass runs whether or not there is
  anything to do, so what it costs when there is nothing is what it costs almost always —
  and that has to be a property of the pass rather than of how much the household has
  already finished.

  Measured on the household's own catalogue before this was asserted: of 2274 queries in a
  minute on an idle server, 2001 were two passes asking after each holding in turn. The
  normalize pass asked five questions of each of 1135 placed holdings to establish that
  none of them was due, and analysis asked six of each to arrive at the set it had
  analysed already.

  Not async. `queries_during/1` reads the repo's telemetry, which is process-wide, so a
  test running beside this one would put its queries in the same stream.
  """

  use Pluteus.DataCase, async: false

  import Pluteus.IngestFixtures

  alias Pluteus.Analysis
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Ingest.Place
  alias Pluteus.Principals

  @t0 ~U[2026-09-18 12:00:00.000000Z]

  @flac %{"codec" => "flac", "muxer" => "flac", "extension" => "flac", "format" => "fmt/279"}

  setup do
    _system = Principals.system!()
    %{inbox: inbox!()}
  end

  describe "spec-04 §3, §8. A pass finds its work at a cost the catalogue does not set" do
    test "a pass over many finished holdings costs what a pass over one does",
         %{inbox: inbox} do
      # Lossy, so each is adopted as its own master on the first pass and none is due on
      # the second. That is the case this is about: the stage runs every minute over a
      # library that is already normalized.
      ingest!(inbox, %{"one.mp3" => media!(:mp3)})
      assert [{_, :adopted}] = Normalize.normalize_due(standard(@flac))

      over_one = cost()

      ingest!(inbox, for(n <- 1..8, into: %{}, do: {"#{n}.mp3", media!(:mp3)}))

      outcomes = Normalize.normalize_due(standard(@flac))

      assert Enum.count(outcomes) == 8
      assert Enum.all?(outcomes, fn {_item, outcome} -> outcome == :adopted end)

      over_nine = cost()

      assert over_nine == over_one,
             "nine holdings cost #{over_nine} queries where one cost #{over_one}"
    end

    test "finding nothing to do takes one question", %{inbox: inbox} do
      ingest!(inbox, %{"one.mp3" => media!(:mp3)})
      Normalize.normalize_due(standard(@flac))

      assert cost() == 1
    end

    test "asking what analysis has to run over costs the same over many as over one",
         %{inbox: inbox} do
      ingest!(inbox, %{"one.mp3" => media!(:mp3)})
      Normalize.normalize_due(standard(@flac))

      over_one = queries_during(fn -> Analysis.inputs() end) |> Enum.count()

      ingest!(inbox, for(n <- 1..8, into: %{}, do: {"#{n}.mp3", media!(:mp3)}))
      Normalize.normalize_due(standard(@flac))

      over_nine = queries_during(fn -> Analysis.inputs() end) |> Enum.count()

      assert Enum.count(Analysis.inputs()) == 9

      assert over_nine == over_one,
             "nine holdings cost #{over_nine} queries where one cost #{over_one}"
    end
  end

  defp ingest!(inbox, files) do
    for {path, bytes} <- files, do: drop!(inbox, path, bytes)
    acquire_settled!(inbox, @t0)
    Place.place_due(inbox)
  end

  defp cost do
    queries_during(fn -> Normalize.normalize_due(standard(@flac)) end) |> length()
  end

  defp standard(format), do: fn class -> if class == :audio, do: format end
end
