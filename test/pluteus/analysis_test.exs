defmodule Pluteus.AnalysisTest do
  @moduledoc """
  Analysis: spec-04 §8, §9 and the conformance criteria they carry. Each
  `describe` names its criterion.
  """

  use Pluteus.DataCase, async: true
  use Oban.Testing, repo: Pluteus.Repo

  import Pluteus.IngestFixtures

  alias Pluteus.Analysis
  alias Pluteus.Analysis.Native
  alias Pluteus.Analysis.Signal
  alias Pluteus.AnalysisTools
  alias Pluteus.Annotations
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Ingest.Place
  alias Pluteus.Principals
  alias Pluteus.StorageFixtures
  alias Pluteus.Workers.AnalyseInput
  alias Pluteus.Workers.ScheduleAnalysis

  @t0 ~U[2026-09-18 12:00:00.000000Z]

  setup do
    {:ok, _system} = Principals.create_principal(%{role: "system"})
    %{inbox: inbox!()}
  end

  describe "the native tool measures on the BEAM" do
    test "a 440 Hz tone at an eighth of full scale", %{inbox: inbox} do
      [tone] = ingest!(inbox, %{"a.flac" => media!(:flac, duration: 3)})
      [input] = Analysis.inputs()
      master = Normalize.master_of(tone.digital_item_id)

      {:ok, %{"measurements" => m}} = Native.analyse(Analysis.request(master, input))

      assert_in_delta m["rms_dbfs"], 20 * :math.log10(0.125 / :math.sqrt(2)), 0.1
      assert_in_delta m["peak_dbfs"], 20 * :math.log10(0.125), 0.1
      assert_in_delta m["loudness_lufs"], -21.76, 0.5
      assert_in_delta m["spectral_centroid_hz"], 440, 40

      {strongest, _} =
        m
        |> Enum.filter(fn {k, _} -> String.starts_with?(k, "chroma_") end)
        |> Enum.max_by(&elem(&1, 1))

      assert strongest == "chroma_a"

      assert map_size(Map.filter(m, fn {k, _} -> String.starts_with?(k, "mel_") end)) == 40
      assert map_size(Map.filter(m, fn {k, _} -> String.starts_with?(k, "mfcc_") end)) == 13
      assert Enum.all?(m, fn {_name, value} -> is_number(value) end)
    end

    test "loudness agrees with ffmpeg's EBU R128 meter where K-weighting matters",
         %{inbox: inbox} do
      [tone] = ingest!(inbox, %{"high.flac" => media!(:flac, frequency: 5_000, duration: 3)})
      [input] = Analysis.inputs()
      master = Normalize.master_of(tone.digital_item_id)

      {:ok, %{"measurements" => m}} = Native.analyse(Analysis.request(master, input))

      assert_in_delta m["loudness_lufs"], ebur128(master.location), 0.2
      assert m["loudness_lufs"] - m["rms_dbfs"] > 3.0
    end

    test "loudness is absent for silence rather than invented" do
      assert Signal.loudness(List.duplicate(0.0, 48_000)) == %{}
      assert Signal.level(List.duplicate(0.0, 100)) == %{}
    end
  end

  describe "21. Analysis runs over the right input, reads the master, and records which" do
    test "a single-stream file is analysed as its manifestation", %{inbox: inbox} do
      [track] = ingest!(inbox, %{"a.flac" => media!(:flac)})

      assert [%{input_id: input_id, stream: nil}] = Analysis.inputs()
      assert input_id == manifestation_of(track)
    end

    test "a container is analysed per audio stream, never as a whole", %{inbox: inbox} do
      [film] = ingest!(inbox, %{"Stalker.mkv" => media!(:film)})
      addresses = film |> manifestation_of() |> Catalog.addresses_of()

      inputs = Analysis.inputs()

      assert [_, _] = inputs
      refute Enum.any?(inputs, &(&1.input_id == manifestation_of(film)))

      for input <- inputs do
        address = Enum.find(addresses, &(&1.id == input.input_id))
        assert address.stream_kind == :audio
      end
    end

    test "a track of a release in one file is analysed over its extent", %{inbox: inbox} do
      ingest!(inbox, %{
        "KoB/album.flac" => media!(:flac, duration: 6),
        "KoB/album.cue" => """
        FILE "album.flac" WAVE
          TRACK 01 AUDIO
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            INDEX 01 00:03:00
        """
      })

      assert [%{start_ms: 0, end_ms: 3_000}, %{start_ms: 3_000, end_ms: 6_000}] =
               Enum.sort_by(Analysis.inputs(), & &1.start_ms)
    end

    test "the derivation names its input and the master it read", %{inbox: inbox} do
      [track] = ingest!(inbox, %{"a.flac" => media!(:flac)})
      [input] = Analysis.inputs()
      {:ok, description} = Analysis.describe(AnalysisTools.Second)

      {:ok, derivation} = Analysis.analyse(AnalysisTools.Second, input, description)

      assert derivation.input_id == manifestation_of(track)
      assert derivation.parameters["asset"] == Normalize.master_of(track.digital_item_id).id
    end

    test "a stream is found by what it is in a master that orders streams otherwise",
         %{inbox: inbox} do
      [film] = ingest!(inbox, %{"Stalker.mkv" => media!(:film)})
      remuxed = StorageFixtures.stored!("remuxed.mkv", media!(:film_remuxed))
      master = %Asset{location: remuxed}

      commentary =
        Enum.find(Analysis.inputs(), &("comment" in &1.stream.stream_disposition))

      russian = Enum.find(Analysis.inputs(), &(&1.stream.stream_language == "rus"))

      assert Analysis.request(master, commentary).stream_index == 0
      assert Analysis.request(master, russian).stream_index == 1
      assert Analysis.request(Repo.get!(Asset, film.id), russian).stream_index == 1
      assert Analysis.request(Repo.get!(Asset, film.id), commentary).stream_index == 2
    end

    test "a stream after one that carries no content keeps its index in the file" do
      probe = %{
        "streams" => [
          %{"codec_type" => "data", "codec_name" => "bin_data", "disposition" => %{}},
          %{"codec_type" => "video", "codec_name" => "h264", "disposition" => %{}},
          %{
            "codec_type" => "audio",
            "codec_name" => "flac",
            "channels" => 2,
            "tags" => %{"language" => "rus"},
            "disposition" => %{"default" => 1}
          }
        ]
      }

      russian = %{
        selector_type: :track,
        stream_kind: :audio,
        stream_language: "rus",
        stream_disposition: [],
        stream_channels: 2,
        stream_ordinal: 1
      }

      assert Analysis.stream_index_in(probe, russian) == 2
      assert Analysis.stream_index_in(probe, %{russian | stream_language: "eng"}) == nil
    end
  end

  describe "22. Two tools' measurements of one input both stand" do
    test "the native and a second tool each keep their own derivation", %{inbox: inbox} do
      [track] = ingest!(inbox, %{"a.flac" => media!(:flac)})
      [input] = Analysis.inputs()

      for tool <- [Native, AnalysisTools.Second] do
        {:ok, description} = Analysis.describe(tool)
        {:ok, _} = Analysis.analyse(tool, input, description)
      end

      tools =
        track
        |> manifestation_of()
        |> Annotations.current_on()
        |> Enum.filter(&(&1.body_type == "measurements"))
        |> Enum.map(&Annotations.present(&1.id).provenance.tool)
        |> Enum.sort()

      assert tools == ["pluteus-native", "second-tool"]
    end
  end

  describe "23. A positional vector or an unknown schema version is refused" do
    test "each is recorded as a finding and nothing is annotated", %{inbox: inbox} do
      [track] = ingest!(inbox, %{"a.flac" => media!(:flac)})
      [input] = Analysis.inputs()

      for tool <- [AnalysisTools.Positional, AnalysisTools.UnknownSchema] do
        {:ok, description} = Analysis.describe(tool)
        assert :refused = Analysis.analyse(tool, input, description)
      end

      assert [%{kind: "response_refused"}, %{kind: "response_refused"}] =
               Enum.filter(Ingest.open_findings(), &(&1.input_id == input.input_id))

      refute Enum.any?(
               Annotations.current_on(manifestation_of(track)),
               &(&1.body_type == "measurements")
             )
    end
  end

  describe "24. A new tool version makes earlier inputs due before any runs at it" do
    test "everything analysed at version 1 is due at version 2", %{inbox: inbox} do
      ingest!(inbox, %{"a.flac" => media!(:flac), "b.flac" => media!(:flac, frequency: 600)})

      {:ok, v1} = Analysis.describe(AnalysisTools.Second)

      for input <- Analysis.due("second-tool", "1"),
          do: {:ok, _} = Analysis.analyse(AnalysisTools.Second, input, v1)

      assert Analysis.due("second-tool", "1") == []

      Process.put(:second_tool_version, "2")
      {:ok, _v2} = Analysis.describe(AnalysisTools.Second)

      assert [_, _] = Analysis.due("second-tool", "2")
    end
  end

  describe "25 and 26. Failures are recorded against the input, tool and version" do
    test "a permanent failure is excluded until cleared or the version changes",
         %{inbox: inbox, actor: actor} do
      ingest!(inbox, %{"a.flac" => media!(:flac)})
      [input] = Analysis.inputs()
      {:ok, description} = Analysis.describe(AnalysisTools.Undecodable)

      assert :failed = Analysis.analyse(AnalysisTools.Undecodable, input, description)

      [finding] = Ingest.open_findings()
      assert finding.input_id == input.input_id
      assert finding.permanent
      assert Repo.get!(Pluteus.Annotations.ToolVersion, finding.tool_version_id).version == "1"
      assert Analysis.due("strict-tool", "1") == []

      Process.put(:strict_tool_version, "2")
      {:ok, _} = Analysis.describe(AnalysisTools.Undecodable)
      assert [_] = Analysis.due("strict-tool", "2")

      {:ok, _} = Ingest.clear_finding(finding.id, actor.id)
      assert [_] = Analysis.due("strict-tool", "1")
    end

    test "a transient failure is retried, and its exhaustion recorded", %{inbox: inbox} do
      ingest!(inbox, %{"a.flac" => media!(:flac)})
      [input] = Analysis.inputs()

      args = %{
        tool: Atom.to_string(AnalysisTools.Unavailable),
        version: "1",
        input_id: input.input_id
      }

      assert {:error, :timeout} = perform_job(AnalyseInput, args, attempt: 1)
      assert Ingest.open_findings() == []

      assert {:error, :timeout} = perform_job(AnalyseInput, args, attempt: 4)

      assert [%{kind: "transient_failure_exhausted", permanent: false}] = Ingest.open_findings()
    end
  end

  describe "27. Emptying the job queue loses no work" do
    test "the schedule finds the same work again from recorded state", %{inbox: inbox} do
      ingest!(inbox, %{"a.flac" => media!(:flac), "b.flac" => media!(:flac, frequency: 600)})

      :ok = perform_job(ScheduleAnalysis, %{})
      queued = Enum.map(all_enqueued(worker: AnalyseInput), & &1.args["input_id"]) |> Enum.sort()

      Repo.delete_all("oban_jobs")

      :ok = perform_job(ScheduleAnalysis, %{})

      assert Enum.sort(Enum.map(all_enqueued(worker: AnalyseInput), & &1.args["input_id"])) ==
               queued

      assert [_, _] = queued
    end

    test "every ingest stage finds unfinished work without a job", %{inbox: inbox} do
      drop!(inbox, "a.flac", media!(:flac))
      Repo.delete_all("oban_jobs")
      acquire_settled!(inbox, @t0)
      Repo.delete_all("oban_jobs")

      assert [{_, :placed}] = Place.place_due(inbox)
      Repo.delete_all("oban_jobs")
      assert [{_, :adopted}] = Normalize.normalize_due(fn _ -> nil end)
    end
  end

  defp ingest!(inbox, files) do
    for {path, bytes} <- files, do: drop!(inbox, path, bytes)
    ids = inbox |> acquire_settled!(@t0) |> acquired()
    Place.place_due(inbox)
    Normalize.normalize_due(fn _class -> nil end)
    ids |> Enum.map(&Ingest.get_acquisition!/1) |> Enum.sort_by(& &1.inbox_path)
  end

  defp ebur128(location) do
    {output, 0} =
      System.cmd(
        "ffmpeg",
        ["-nostdin", "-i", Pluteus.Storage.path(location), "-af", "ebur128", "-f", "null", "-"],
        stderr_to_stdout: true
      )

    [_, integrated] = Regex.run(~r/Integrated loudness:\s+I:\s+(-?[0-9.]+) LUFS/, output)
    String.to_float(integrated)
  end

  defp manifestation_of(acquisition),
    do: Repo.get!(DigitalItem, acquisition.digital_item_id).manifestation_id
end
