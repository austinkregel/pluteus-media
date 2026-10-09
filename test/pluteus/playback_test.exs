defmodule Pluteus.PlaybackTest do
  @moduledoc """
  What playing a holding acts on (spec-10 criterion 40, §8.1; spec-04 §6.4).

  Built through the real pipeline rather than by assembling rows, because what is under
  test is that the bytes placement wrote and the region it recorded are what a client is
  pointed at. A fixture that set the extent itself would assert agreement with itself.
  """

  use Pluteus.DataCase, async: true

  import Pluteus.IngestFixtures

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Profile
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Playback
  alias Pluteus.Principals

  setup do
    {:ok, principal} = Principals.create_principal(%{role: "member"})

    %{inbox: inbox!(), principal: principal, profile: %Profile{}}
  end

  describe "40. A track of a release held in one file plays as a region of it" do
    test "each track resolves to the release's own bytes, with its recorded bounds",
         %{inbox: inbox, principal: principal, profile: profile} do
      # The criterion's own point: nothing is cut, so both tracks name one asset and
      # differ only in where they begin and end.
      %{tracks: [so_what, freddie]} = a_release_in_one_file(inbox)

      assert {:ok, first} = Playback.for_work(so_what, principal.id, profile)
      assert {:ok, second} = Playback.for_work(freddie, principal.id, profile)

      assert [%{asset_id: asset}] = first.parts
      assert [%{asset_id: ^asset}] = second.parts

      assert {first.from_ms, first.to_ms} == {0, 3_000}
      assert {second.from_ms, second.to_ms} == {3_000, 6_000}
    end

    test "the bounds are the ones placement recorded, not ones computed here",
         %{inbox: inbox, principal: principal, profile: profile} do
      %{tracks: [_so_what, freddie]} = a_release_in_one_file(inbox)

      [address_id] = Catalog.associated(manifestation_of_work(freddie), "extent-of")
      recorded = Repo.get!(Address, address_id)

      assert {:ok, played} = Playback.for_work(freddie, principal.id, profile)

      assert {played.from_ms, played.to_ms} == {recorded.start_ms, recorded.end_ms}
    end

    test "the release itself plays whole, with no bounds",
         %{inbox: inbox, principal: principal, profile: profile} do
      %{release: release} = a_release_in_one_file(inbox)

      assert {:ok, %{from_ms: nil, to_ms: nil}} =
               Playback.for_work(release, principal.id, profile)
    end
  end

  describe "§8.1. A holding carried by its own file plays as that file" do
    test "it resolves to its normalized master and says what type it is",
         %{inbox: inbox, principal: principal, profile: profile} do
      reading = a_reading(inbox, [%{"track" => "1"}])

      assert {:ok, played} = Playback.for_work(reading, principal.id, profile)

      assert [%{media_type: "audio/flac"}] = played.parts
      assert {played.from_ms, played.to_ms} == {nil, nil}
    end
  end

  describe "A holding in several files is one sequence, in order" do
    test "the parts come back in the order they were read, each with its own length",
         %{inbox: inbox, principal: principal, profile: profile} do
      reading = a_reading(inbox, [%{"track" => "1/2"}, %{"track" => "2/2"}])

      assert {:ok, played} = Playback.for_work(reading, principal.id, profile)

      assert [first, second] = played.parts
      refute first.asset_id == second.asset_id

      for part <- played.parts do
        assert part.duration_ms > 0,
               "a part of a sequence has no measured length, so no position can be placed in it"
      end
    end
  end

  describe "§12.3, §12.4. Playing a holding fills a queue it can carry on from" do
    test "playing a release queues its tracks in order, each from the release",
         %{inbox: inbox} do
      %{release: release, tracks: tracks} = a_release_in_one_file(inbox)

      assert {entries, 0} = Playback.queue_for(release)

      assert Enum.map(entries, & &1.res_id) == tracks

      for entry <- entries do
        assert entry.queued_from == release,
               "an entry does not record the grouping it was queued from"
      end
    end

    test "playing a track queues the release and starts at that track", %{inbox: inbox} do
      # What follows a track is the rest of its release rather than nothing, which is
      # also what makes §12.4's question — whether a next member exists — answerable.
      %{release: release, tracks: [first, second]} = a_release_in_one_file(inbox)

      assert {entries, 1} = Playback.queue_for(second)

      assert Enum.map(entries, & &1.res_id) == [first, second]
      assert Enum.all?(entries, &(&1.queued_from == release))
    end

    test "a holding that is a member of nothing is a queue of one, from nothing",
         %{inbox: inbox} do
      reading = a_reading(inbox, [%{"track" => "1"}])

      assert {[%{res_id: ^reading, queued_from: nil}], 0} = Playback.queue_for(reading)
    end
  end

  describe "§5.2. Nothing to play is an answer, and each reason is its own" do
    test "a holding the household holds no file for says so",
         %{principal: principal, profile: profile} do
      {:ok, %{work: work}} =
        Catalog.create_work(%{nomen_string: "A letter nobody scanned", provenance: :automatic})

      assert {:error, {:holds_no_file, _id} = refusal} =
               Playback.for_work(work.id, principal.id, profile)

      assert Playback.why(refusal) =~ "holds no file for it"
    end

    test "a holding whose bytes are not normalized yet says that instead",
         %{inbox: inbox, principal: principal, profile: profile} do
      # Placed but not normalized: there is a file and no master to play from, which
      # resolves itself and so is not the same fact as holding no file.
      reading = a_reading(inbox, [%{"track" => "1"}], normalize: false)

      assert {:error, {:not_normalized, _id} = refusal} =
               Playback.for_work(reading, principal.id, profile)

      assert Playback.why(refusal) =~ "not been normalized"
    end
  end

  defp a_release_in_one_file(inbox) do
    prefix = unique_prefix()

    placed =
      ingest!(inbox, %{
        "#{prefix}/album.flac" => media!(:flac, duration: 6),
        "#{prefix}/album.cue" => """
        TITLE "Kind of Blue"
        PERFORMER "Miles Davis"
        FILE "album.flac" WAVE
          TRACK 01 AUDIO
            TITLE "So What"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "Freddie Freeloader"
            INDEX 01 00:03:00
        """
      })

    album = Enum.find(placed, &(&1.media_class == :audio))
    release = manifestation_of(album)

    [%{part_id: medium}] = Catalog.parts_of(release)
    parts = Catalog.parts_of(medium)

    %{
      release: work_of_manifestation(release),
      tracks: Enum.map(parts, &work_of_manifestation(&1.part_id))
    }
  end

  defp a_reading(inbox, parts, opts \\ []) do
    prefix = unique_prefix()

    files =
      for {part, number} <- Enum.with_index(parts, 1), into: %{} do
        {"#{prefix}/#{number}.flac",
         media!(:flac,
           duration: 2,
           tags:
             Map.merge(
               %{
                 "genre" => "Audiobook",
                 "album" => "A Wizard of Earthsea",
                 "artist" => "Ursula K. Le Guin",
                 "title" => "Chapter #{number}"
               },
               part
             )
         )}
      end

    [first | _rest] = ingest!(inbox, files, opts)

    work_of_manifestation(manifestation_of(first))
  end

  defp ingest!(inbox, files, opts \\ []) do
    for {path, bytes} <- files, do: drop!(inbox, path, bytes)

    ids = inbox |> acquire_settled!() |> acquired()

    place_all!(inbox)
    if Keyword.get(opts, :normalize, true), do: Normalize.normalize_due()

    ids
    |> Enum.map(&Ingest.get_acquisition!/1)
    |> Enum.sort_by(& &1.inbox_path)
  end

  defp manifestation_of(acquisition) do
    Repo.get!(DigitalItem, acquisition.digital_item_id).manifestation_id
  end

  defp manifestation_of_work(work_id) do
    [expression | _rest] = Catalog.expressions_of(work_id)
    [manifestation | _more] = Catalog.manifestations_of(expression.id)

    manifestation.id
  end

  defp work_of_manifestation(manifestation_id) do
    [expression | _rest] = Catalog.expressions_in(manifestation_id)

    expression.work_id
  end
end
