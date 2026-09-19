defmodule Pluteus.Ingest.NormalizationTest do
  @moduledoc """
  Normalization: spec-04 §7 and the conformance criteria it carries. Each
  `describe` names its criterion.
  """

  use Pluteus.DataCase, async: true

  import Pluteus.IngestFixtures

  alias Pluteus.Assets
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Ingest.Place
  alias Pluteus.Lifecycle
  alias Pluteus.Principals
  alias Pluteus.Storage
  alias Pluteus.StorageFixtures

  @t0 ~U[2026-09-18 12:00:00.000000Z]

  @flac %{"codec" => "flac", "muxer" => "flac", "extension" => "flac", "format" => "fmt/279"}
  @wav %{"codec" => "pcm_s16le", "muxer" => "wav", "extension" => "wav", "format" => "fmt/141"}
  @eight_bit %{"codec" => "pcm_u8", "muxer" => "wav", "extension" => "wav", "format" => "fmt/141"}

  setup do
    _system = Principals.system!()
    %{inbox: inbox!()}
  end

  describe "28. One asset per digital item holds the Normalized role" do
    test "a lossy acquisition is its own master and nothing is written", %{inbox: inbox} do
      [track] = ingest!(inbox, %{"a.mp3" => media!(:mp3)})

      assert [{_, :adopted}] = Normalize.normalize_due(standard(@flac))

      assert Normalize.master_of(track.digital_item_id).id == track.id
      assert [_one] = Catalog.assets_of(track.digital_item_id)
      assert Assets.role_classes_of(track.id) == [:acquired, :normalized]
    end

    test "a lossless acquisition is re-encoded, and the copy decodes to the original",
         %{inbox: inbox} do
      [track] = ingest!(inbox, %{"a.wav" => media!(:wav)})

      assert [{_, :re_encoded}] = Normalize.normalize_due(standard(@flac))

      master = Normalize.master_of(track.digital_item_id)
      refute master.id == track.id
      assert master.format == "fmt/279"
      assert master.essence == :lossless
      assert master.location == Ingest.location_for(master.id)
      assert decoded(master.location) == decoded(track.location)
      assert Assets.role_classes_of(track.id) == [:acquired]
      assert Assets.role_classes_of(master.id) == [:normalized]
      cleanup(master.id)
    end

    test "an acquisition already in the standard format is its own master", %{inbox: inbox} do
      [track] = ingest!(inbox, %{"a.flac" => media!(:flac)})

      assert [{_, :adopted}] = Normalize.normalize_due(standard(@flac))
      assert Normalize.master_of(track.digital_item_id).id == track.id
    end

    test "a class with no standard format adopts its lossless acquisition", %{inbox: inbox} do
      [still] = ingest!(inbox, %{"a.png" => media!(:png)})

      assert [{_, :adopted}] = Normalize.normalize_due(fn _class -> nil end)
      assert Normalize.master_of(still.digital_item_id).id == still.id
    end

    test "a pass over normalized holdings does nothing", %{inbox: inbox} do
      ingest!(inbox, %{"a.flac" => media!(:flac), "b.mp3" => media!(:mp3)})
      Normalize.normalize_due(standard(@flac))

      assert Normalize.normalize_due(standard(@flac)) == []
    end

    test "a changed standard takes the role from an original without recycling it",
         %{inbox: inbox} do
      [track] = ingest!(inbox, %{"a.flac" => media!(:flac)})
      Normalize.normalize_due(standard(@flac))

      assert [{_, :re_encoded}] = Normalize.normalize_due(standard(@wav))

      master = Normalize.master_of(track.digital_item_id)
      cleanup(master.id)
      assert master.format == "fmt/141"
      assert Assets.role_classes_of(track.id) == [:acquired]
      assert {:live, _} = Lifecycle.state(track.id)
    end

    test "a changed standard recycles a previous copy", %{inbox: inbox} do
      [track] = ingest!(inbox, %{"a.wav" => media!(:wav)})
      Normalize.normalize_due(standard(@flac))
      copy = Normalize.master_of(track.digital_item_id)
      cleanup(copy.id)

      assert [{_, :adopted}] = Normalize.normalize_due(standard(@wav))

      assert Normalize.master_of(track.digital_item_id).id == track.id
      assert {:recycled, _, _} = Lifecycle.state(copy.id)
      assert Storage.exists?(copy.location)
    end

    test "restoring a replaced master from the bin is refused", %{inbox: inbox} do
      [track] = ingest!(inbox, %{"a.wav" => media!(:wav)})
      Normalize.normalize_due(standard(@flac))
      copy = Normalize.master_of(track.digital_item_id)
      cleanup(copy.id)
      Normalize.normalize_due(standard(@wav))
      {:recycled, _, recycling} = Lifecycle.state(copy.id)

      # The sandbox never commits, so checks deferred by the passes above are
      # still pending. They run now, leaving only the restore to be checked.
      Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")
      Repo.query!("SET CONSTRAINTS ALL DEFERRED")

      assert_raise Postgrex.Error, ~r/one_normalized_master/, fn ->
        Repo.transaction(fn ->
          {:ok, _} = Lifecycle.restore(recycling.id)
          Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")
        end)
      end
    end

    test "the database refuses a second live master", %{inbox: inbox} do
      [track] = ingest!(inbox, %{"a.mp3" => media!(:mp3)})
      Normalize.normalize_due(standard(@flac))

      assert_raise Postgrex.Error, ~r/one_normalized_master/, fn ->
        Repo.transaction(fn ->
          {:ok, %{asset: _}} =
            Catalog.create_asset(
              track.digital_item_id,
              %{
                location: StorageFixtures.stored!("second.mp3", media!(:mp3, frequency: 600)),
                essence: :lossy,
                verification_interval_seconds: 86_400,
                roles: [%{role_class: :normalized, role: "standardized-master"}]
              },
              "second.mp3"
            )

          Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")
        end)
      end
    end
  end

  describe "26. A failed normalization is recorded against the digital item" do
    test "a re-encode that loses fidelity is a finding, never a master", %{inbox: inbox} do
      [track] = ingest!(inbox, %{"a.flac" => media!(:flac)})
      assets_before = Catalog.assets_of(track.digital_item_id)

      assert [{digital_item_id, :finding}] = Normalize.normalize_due(standard(@eight_bit))

      assert digital_item_id == track.digital_item_id

      assert [
               %{
                 stage: :normalize,
                 kind: "normalization_lost_fidelity",
                 digital_item_id: ^digital_item_id
               }
             ] =
               Ingest.open_findings()

      [%{detail: %{"removed" => removed}}] = Ingest.open_findings()
      refute Storage.exists?(removed)
      assert Catalog.assets_of(track.digital_item_id) == assets_before
      assert Normalize.master_of(track.digital_item_id) == nil
      assert Normalize.normalize_due(standard(@eight_bit)) == []
    end

    test "clearing the finding makes the holding due again", %{inbox: inbox, actor: actor} do
      ingest!(inbox, %{"a.flac" => media!(:flac)})
      Normalize.normalize_due(standard(@eight_bit))
      [finding] = Ingest.open_findings()

      {:ok, _} = Ingest.clear_finding(finding.id, actor.id)

      assert [{_, :re_encoded}] = Normalize.normalize_due(standard(@wav))
      cleanup_masters()
    end
  end

  describe "10. Removing a companion does not remove the described holding's master" do
    test "recycling the cover leaves the track's normalized master", %{inbox: inbox, actor: actor} do
      placed =
        ingest!(inbox, %{
          "KoB/cover.jpg" => media!(:jpeg),
          "KoB/01.wav" => media!(:wav)
        })

      Normalize.normalize_due(standard(@flac))
      cleanup_masters()

      cover = Enum.find(placed, &(&1.media_class == :companion))
      track = Enum.find(placed, &(&1.media_class == :audio))
      master = Normalize.master_of(track.digital_item_id)

      cover_work =
        Repo.get!(DigitalItem, cover.digital_item_id).manifestation_id
        |> Catalog.expressions_in()
        |> hd()
        |> Map.fetch!(:work_id)

      {:ok, recycling} = Lifecycle.recycle(cover_work, actor.id)

      refute master.id in Lifecycle.contents(recycling.id)
      assert {:live, _} = Lifecycle.state(master.id)
    end
  end

  defp ingest!(inbox, files) do
    for {path, bytes} <- files, do: drop!(inbox, path, bytes)
    ids = inbox |> acquire_settled!(@t0) |> acquired()
    Place.place_due(inbox)
    ids |> Enum.map(&Ingest.get_acquisition!/1) |> Enum.sort_by(& &1.inbox_path)
  end

  defp standard(format), do: fn class -> if class == :audio, do: format end

  defp decoded(location) do
    {hash, 0} =
      System.cmd("ffmpeg", ~w(-loglevel error -i #{Storage.path(location)} -map 0:a -f md5 -))

    hash
  end

  # A master written during the test lies in primary storage under an
  # identifier the test did not mint; its bytes go when the test exits.
  defp cleanup_masters do
    Repo.all(from a in Asset, select: a.id) |> Enum.each(&cleanup/1)
  end
end
