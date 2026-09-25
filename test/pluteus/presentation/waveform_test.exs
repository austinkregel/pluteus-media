defmodule Pluteus.Presentation.WaveformTest do
  @moduledoc """
  [spec-10] §11.4's two waveform artefacts, and criterion 30: a surface does not offer
  a waveform zoom finer than the stored artefact.
  """

  use Pluteus.DataCase, async: true

  import Pluteus.IngestFixtures

  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Ingest.Place
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Generate
  alias Pluteus.Presentation.Registry
  alias Pluteus.Presentation.Waveform
  alias Pluteus.Principals
  alias Pluteus.Storage

  @t0 ~U[2026-09-18 12:00:00.000000Z]

  setup do
    _system = Principals.system!()
    %{inbox: inbox!()}
  end

  # Under a prefix of its own, because two async tests dropping one relative path
  # contend on the sighting and acquisition rows for as long as the slower one runs.
  defp ingest!(inbox, files) do
    prefix = unique_prefix()
    for {path, bytes} <- files, do: drop!(inbox, Path.join(prefix, path), bytes)
    ids = inbox |> acquire_settled!(@t0) |> acquired()
    Place.place_due(inbox)
    Normalize.normalize_due()
    ids |> Enum.map(&Ingest.get_acquisition!/1) |> Enum.sort_by(& &1.inbox_path)
  end

  defp manifestation_of(acquisition),
    do: Repo.get!(DigitalItem, acquisition.digital_item_id).manifestation_id

  defp a_recording(inbox, opts \\ []) do
    duration = Keyword.get(opts, :duration, 2)
    name = Keyword.get(opts, :name, "KoB/01.flac")

    [track] = ingest!(inbox, %{name => media!(:flac, duration: duration)})
    manifestation_of(track)
  end

  defp made!(subject, profile) do
    {:ok, made} = Generate.run(subject, profile)
    on_exit(fn -> Storage.delete(made.location) end)
    made
  end

  defp peaks_of(made), do: Jason.decode!(Storage.read(made.location))["peaks"]

  describe "an overview is a fixed count however long the recording is" do
    test "a two-second recording yields the registry's point count", %{inbox: inbox} do
      made = made!(a_recording(inbox, duration: 2), "waveform-overview-1000")

      assert made.media_type == "application/json"
      assert length(peaks_of(made)) == Registry.waveform_overview()["points"]
    end

    test "a longer recording yields the same count and a similar size", %{inbox: inbox} do
      short =
        made!(a_recording(inbox, duration: 2, name: "a/short.flac"), "waveform-overview-1000")

      long = made!(a_recording(inbox, duration: 8, name: "b/long.flac"), "waveform-overview-1000")

      assert length(peaks_of(short)) == length(peaks_of(long))

      # A constant few kilobytes for a track or a nine-hour reading, which is what a
      # transport bar needs and what distinguishes this from the detail waveform.
      assert_in_delta long.size, short.size, short.size
    end

    test "every peak is a byte, and a tone is not silence", %{inbox: inbox} do
      peaks = peaks_of(made!(a_recording(inbox), "waveform-overview-1000"))

      assert Enum.all?(peaks, &(&1 >= 0 and &1 <= 255))
      assert Enum.max(peaks) > 0, "a 440 Hz tone measured as silence"
    end

    test "it carries no geometry, because it is not an image", %{inbox: inbox} do
      made = made!(a_recording(inbox), "waveform-overview-1000")

      assert made.width == nil
      assert made.height == nil
    end
  end

  describe "a detail waveform's size scales with duration" do
    test "the point count is the duration times the rate", %{inbox: inbox} do
      made = made!(a_recording(inbox, duration: 4), "waveform-detail-10")

      # Four seconds at ten points a second.
      assert_in_delta length(peaks_of(made)), 40, 2
    end

    test "a finer rate yields proportionally more points", %{inbox: inbox} do
      subject = a_recording(inbox, duration: 2)

      coarse = made!(subject, "waveform-detail-10")
      fine = made!(subject, "waveform-detail-100")

      assert length(peaks_of(fine)) > length(peaks_of(coarse)) * 5
    end
  end

  describe "30. A surface does not offer a zoom finer than the stored artefact" do
    test "an artefact states the resolution it was measured at", %{inbox: inbox} do
      made = made!(a_recording(inbox, duration: 2), "waveform-detail-10")

      assert made.descriptor["points_per_second"] == 10
      assert made.descriptor["duration_ms"] > 0
      assert made.descriptor["points_measured"] > 0
    end

    test "a zoom at or below the stored resolution is supported", %{inbox: inbox} do
      made = made!(a_recording(inbox, duration: 2), "waveform-detail-10")

      assert Presentation.supports_zoom?(made, 10)
      assert Presentation.supports_zoom?(made, 5)
      assert Presentation.supports_zoom?(made, 1)
    end

    test "a zoom finer than the stored resolution is not", %{inbox: inbox} do
      made = made!(a_recording(inbox, duration: 2), "waveform-detail-10")

      # Decimating a stored waveform is a coarser view of the same shape. Interpolating
      # one draws a shape the audio does not have.
      refute Presentation.supports_zoom?(made, 11)
      refute Presentation.supports_zoom?(made, 100)
    end

    test "an overview's resolution follows from its count and the duration",
         %{inbox: inbox} do
      made = made!(a_recording(inbox, duration: 10), "waveform-overview-1000")

      # A thousand points over ten seconds is a hundred a second.
      assert_in_delta Waveform.resolution(made.descriptor), 100, 5
    end

    test "the profile chosen for a zoom is the coarsest that reaches it" do
      # Ten seconds: the overview measures a hundred points a second over it, and the
      # detail profiles ten and a hundred.
      assert Presentation.waveform_for_zoom(5, 10_000)["name"] == "waveform-detail-10"
      assert Presentation.waveform_for_zoom(10, 10_000)["name"] == "waveform-detail-10"
    end

    test "a tie goes to the artefact already generated at ingest" do
      # Over ten seconds the overview's thousand points are a hundred a second, which
      # is exactly the finest detail profile. Both reach a zoom of fifty; the overview
      # is already there and the other would be encoded to say the same thing.
      assert Presentation.waveform_for_zoom(50, 10_000)["name"] == "waveform-overview-1000"
      assert "waveform-overview-1000" in Registry.generated_at_ingest()
    end

    test "over a long recording the fixed-count overview is too coarse" do
      # Nine hours: a thousand points is one per thirty-two seconds, so a zoom of one
      # point a second has to come from a detail profile.
      assert Presentation.waveform_for_zoom(1, 32_400_000)["name"] == "waveform-detail-10"
    end

    test "a zoom nothing reaches is answered with nothing, not with a stretch" do
      # A surface asking for finer than anything measured is told so.
      assert Presentation.waveform_for_zoom(10_000, 10_000) == nil
    end
  end

  describe "the peaks are peaks, not means" do
    test "a burst is not averaged away", %{inbox: inbox} do
      # `bursts` is a tone in 120 ms bursts once a second. Averaging would flatten the
      # bursts towards the silence between them; taking peaks keeps them.
      [track] = ingest!(inbox, %{"a/bursts.flac" => media!(:bursts)})
      made = made!(manifestation_of(track), "waveform-overview-1000")

      peaks = peaks_of(made)

      assert Enum.max(peaks) > 0
      assert Enum.min(peaks) == 0, "the silence between bursts was filled in"
    end
  end
end
