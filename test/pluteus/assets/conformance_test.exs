defmodule Pluteus.Assets.ConformanceTest do
  @moduledoc """
  Behavioural conformance with spec-03 §9.

  Each `describe` block states one numbered criterion.
  """

  use Pluteus.DataCase, async: true
  use Oban.Testing, repo: Pluteus.Repo

  alias Pluteus.Annotations
  alias Pluteus.Assets
  alias Pluteus.Backup
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.Reconstruction
  alias Pluteus.Dedup
  alias Pluteus.Formats
  alias Pluteus.Lifecycle
  alias Pluteus.Principals
  alias Pluteus.Storage
  alias Pluteus.StorageFixtures
  alias Pluteus.Workers.VerifyAsset

  setup do
    {:ok, principal} = Principals.create_principal(%{role: "member"})

    {:ok, %{manifestation: manifestation}} =
      Catalog.create_work("Letter from Ada, 12 April 1943")

    {:ok, %{digital_item: letter}} =
      Catalog.create_digital_item(manifestation.id, "Letter from Ada, 12 April 1943")

    %{principal: principal, letter: letter, manifestation: manifestation}
  end

  describe "1. An asset references one digital item and carries at least one role" do
    test "one with a role in a normative class is accepted", %{letter: letter} do
      assert {:ok, %{asset: asset}} = store(letter.id, roles: [acquired: "original-scan"])

      assert asset.digital_item_id == letter.id
      assert Assets.role_classes_of(asset.id) == [:acquired]
    end

    test "one carrying both Acquired and Normalized is accepted", %{letter: letter} do
      assert {:ok, %{asset: asset}} =
               store(letter.id, roles: [acquired: "original", normalized: "standardized-master"])

      assert Assets.role_classes_of(asset.id) == [:acquired, :normalized]
    end

    test "one with no role at all is refused at commit", %{letter: letter} do
      assert_raise Postgrex.Error, fn ->
        Repo.transaction(fn ->
          {:ok, _} = store(letter.id, roles: [])
          Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")
        end)
      end
    end
  end

  describe "2. An asset past its verification interval is reported unverified" do
    test "a check ninety-one days ago on a ninety-day interval is overdue", %{letter: letter} do
      asset = stored!(letter.id)
      {:ok, _} = Assets.record_verification(asset.id, :verified, days_ago(91))

      assert asset.id in ids(Assets.unverified())
    end
  end

  describe "3. An asset never verified is reported unverified" do
    test "a new asset is not presumed sound", %{letter: letter} do
      assert stored!(letter.id).id in ids(Assets.unverified())
    end
  end

  describe "4. A pass that fails to run is distinguishable from one that found nothing wrong" do
    test "a pass that ran leaves a verified record; one that failed leaves none", %{
      letter: letter
    } do
      checked = stored!(letter.id)
      broken = stored!(letter.id)

      Repo.update_all(from(a in Asset, where: a.id == ^broken.id),
        set: [digest_algorithm: "md4-of-my-own-devising"]
      )

      :ok = perform_job(VerifyAsset, %{asset_id: checked.id})
      assert_raise ArgumentError, fn -> perform_job(VerifyAsset, %{asset_id: broken.id}) end

      assert [%{outcome: :verified}] = Assets.verifications_of(checked.id)
      assert Assets.verifications_of(broken.id) == []

      refute checked.id in ids(Assets.unverified())
      assert broken.id in ids(Assets.unverified())
    end
  end

  describe "5. A digest mismatch is recorded and surfaced, and nothing is overwritten" do
    test "the mismatch is a finding, apart from sound and unchecked assets", %{letter: letter} do
      altered = stored!(letter.id)
      sound = stored!(letter.id)
      unchecked = stored!(letter.id)
      :ok = Storage.put(altered.location, "not the letter")

      {:ok, _} = Assets.verify(altered.id)
      {:ok, _} = Assets.verify(sound.id)

      assert [%{asset_id: asset_id, outcome: :mismatched}] = Assets.findings()
      assert asset_id == altered.id

      assert unchecked.id in ids(Assets.unverified())
      refute sound.id in ids(Assets.unverified())
    end

    test "the recorded digest and the bytes are left as found", %{letter: letter} do
      asset = stored!(letter.id)
      :ok = Storage.put(asset.location, "not the letter")

      {:ok, _} = Assets.verify(asset.id)

      assert Repo.get!(Asset, asset.id).digest == asset.digest
      assert Storage.read(asset.location) == "not the letter"
    end
  end

  describe "6. Re-encoding lossy essence is rejected; lossless into the standard codec is not" do
    test "lossy is refused", %{letter: letter} do
      lossy = stored!(letter.id, essence: :lossy)

      assert {:error, :source, {:only_lossless_essence_is_re_encoded, :lossy}, _} =
               Assets.normalize(lossy.id, attrs(roles: []), "1943-04-12.jxl")
    end

    test "unknown and not-applicable essence are refused as lossy is", %{letter: letter} do
      for essence <- [:unknown, :not_applicable] do
        asset = stored!(letter.id, essence: essence)

        assert {:error, :source, {:only_lossless_essence_is_re_encoded, ^essence}, _} =
                 Assets.normalize(asset.id, attrs(roles: []), "1943-04-12.jxl")

        assert Asset.normalization_plan(asset) == :adopt
      end
    end

    test "lossless is accepted", %{letter: letter} do
      lossless = stored!(letter.id)

      assert {:ok, %{normalized: _master}} =
               Assets.normalize(lossless.id, attrs(roles: []), "1943-04-12.jxl")
    end
  end

  describe "7. Discarding an original for a recompression needs a verified reconstruction" do
    setup %{letter: letter} do
      original = stored!(letter.id, bytes: StorageFixtures.png("original scan"))

      {:ok, %{normalized: recompression}} =
        Assets.normalize(original.id, attrs(roles: []), "1943-04-12.jxl")

      %{original: original, recompression: recompression}
    end

    test "bytes rebuilt identical to the original let it go", context do
      rebuilt = StorageFixtures.stored!("rebuilt.tiff", Storage.read(context.original.location))

      assert {:ok, recycling} =
               Assets.discard_original(
                 context.original.id,
                 context.recompression.id,
                 rebuilt,
                 context.principal.id
               )

      assert Lifecycle.contents(recycling.id) |> Enum.member?(context.original.id)
      refute Lifecycle.contents(recycling.id) |> Enum.member?(context.recompression.id)

      assert Assets.role_classes_of(context.recompression.id) == [:acquired, :normalized]
      assert [%Reconstruction{}] = Repo.all(Reconstruction)
    end

    test "bytes that differ from the original are refused, and nothing changes", context do
      rebuilt = StorageFixtures.stored!("rebuilt.tiff", StorageFixtures.png("a near miss"))

      assert {:error, :reconstruction_does_not_match} =
               Assets.discard_original(
                 context.original.id,
                 context.recompression.id,
                 rebuilt,
                 context.principal.id
               )

      assert {:live, _res} = Lifecycle.state(context.original.id)
      assert Assets.role_classes_of(context.recompression.id) == [:normalized]
      assert Repo.all(Reconstruction) == []
    end

    test "a reconstruction that was never produced is refused", context do
      assert {:error, {:reconstruction_unreadable, :enoent}} =
               Assets.discard_original(
                 context.original.id,
                 context.recompression.id,
                 "rebuilt/never-written.tiff",
                 context.principal.id
               )
    end

    test "purging the discarded original leaves the recompression standing", context do
      rebuilt = StorageFixtures.stored!("rebuilt.tiff", Storage.read(context.original.location))

      {:ok, recycling} =
        Assets.discard_original(
          context.original.id,
          context.recompression.id,
          rebuilt,
          context.principal.id
        )

      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())

      assert [standing] = Catalog.assets_of(context.letter.id)
      assert standing.id == context.recompression.id
    end
  end

  describe "8. Deleting a normalized copy leaves the original; deleting the original takes it" do
    setup %{letter: letter} do
      original = stored!(letter.id)
      {:ok, %{normalized: copy}} = Assets.normalize(original.id, attrs(roles: []), "copy.jxl")
      %{original: original, copy: copy}
    end

    test "the copy alone may go", %{original: original, copy: copy, principal: principal} do
      {:ok, recycling} = Lifecycle.recycle(copy.id, principal.id)

      refute original.id in Lifecycle.contents(recycling.id)
    end

    test "the original takes the copy", %{original: original, copy: copy, principal: principal} do
      {:ok, recycling} = Lifecycle.recycle(original.id, principal.id)

      assert copy.id in Lifecycle.contents(recycling.id)
    end
  end

  describe "8, per part. An original supports the copy of its own part and no other" do
    test "disc two's original takes disc two's copy and leaves disc one's", context do
      [disc_one, disc_two] =
        for part <- [1, 2] do
          original = stored!(context.letter.id, part_sequence: part)

          copy =
            stored!(context.letter.id,
              part_sequence: part,
              roles: [normalized: "standardized-master"]
            )

          %{original: original, copy: copy}
        end

      assert Assets.coupled_to(disc_two.original.id) == [disc_two.copy.id]

      {:ok, recycling} = Lifecycle.recycle(disc_two.original.id, context.principal.id)

      assert disc_two.copy.id in Lifecycle.contents(recycling.id)
      refute disc_one.copy.id in Lifecycle.contents(recycling.id)
    end
  end

  describe "9. Every asset carries a format identified from its bytes, not its filename" do
    test "a PNG filed under a .tiff name is recorded as PNG", %{letter: letter} do
      asset = stored!(letter.id, file_name: "1943-04-12.tiff")

      assert asset.format == "fmt/11"
    end

    test "bytes nothing recognizes are UNKNOWN, even under a known extension", %{letter: letter} do
      asset = stored!(letter.id, file_name: "noise.bin", bytes: :binary.copy(<<1, 2, 3>>, 400))

      assert asset.format == Formats.unknown()
    end

    test "a format cannot be supplied in place of being read", %{letter: letter} do
      assert_raise ArgumentError, fn ->
        Catalog.create_asset(letter.id, Map.put(attrs(), :format, "fmt/353"), "letter.tiff")
      end
    end

    test "a measurement taken of other bytes is refused", %{letter: letter} do
      {:ok, elsewhere} =
        Catalog.measure(StorageFixtures.stored!("other.png", StorageFixtures.png("other")))

      assert_raise ArgumentError, ~r/is not one of/, fn ->
        Catalog.create_asset(letter.id, Map.put(attrs(), :measurement, elsewhere), "letter.tiff")
      end
    end

    test "a measurement taken of the same bytes stands in for reading them", %{letter: letter} do
      attrs = attrs()
      {:ok, measurement} = Catalog.measure(attrs.location)

      {:ok, %{asset: asset}} =
        Catalog.create_asset(letter.id, Map.put(attrs, :measurement, measurement), "letter.tiff")

      assert {asset.size, asset.digest, asset.format} ==
               {measurement.size, measurement.digest, measurement.format}
    end

    test "size and digest are read too", %{letter: letter} do
      bytes = StorageFixtures.png("measured")
      asset = stored!(letter.id, bytes: bytes)

      assert asset.size == byte_size(bytes)
      assert asset.digest == :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
      assert asset.digest_algorithm == "sha-256"
    end
  end

  describe "10. Derived assets and derived annotations are excluded from backup" do
    test "a thumbnail is not copied; the scan is", %{letter: letter} do
      scan = stored!(letter.id)
      thumbnail = stored!(letter.id, roles: [derived: "thumbnail"])
      spare = stored!(letter.id, roles: [redundant: "offsite-copy"])

      backed_up = ids(Repo.all(Backup.selection("assets")))

      assert scan.id in backed_up
      refute thumbnail.id in backed_up
      refute spare.id in backed_up
    end

    test "a machine transcript is not copied; a person's note is", context do
      whisper =
        derivation!("whisper", "large-v3", context.manifestation.id)

      {:ok, transcript} =
        Annotations.annotate(%{
          target_id: context.manifestation.id,
          body_type: "transcript",
          body: %{"text" => "Dear Ada"},
          derivation_id: whisper.id
        })

      {:ok, note} =
        Annotations.annotate(%{
          target_id: context.manifestation.id,
          body_type: "note",
          body: %{"text" => "written the week before the evacuation"},
          principal_id: context.principal.id
        })

      backed_up = ids(Repo.all(Backup.selection("annotations")))

      refute transcript.id in backed_up
      assert note.id in backed_up
    end

    test "the catalog is included, and no table is left unclassified" do
      tables =
        Repo.query!("""
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
        """).rows
        |> List.flatten()
        |> Enum.sort()

      classification = Backup.classification()

      assert tables == classification |> Map.keys() |> Enum.sort()

      for table <- ~w(res nomens works expressions manifestations digital_items events) do
        assert classification[table] == :whole
      end
    end
  end

  describe "11. Two byte-identical assets of one digital item are not duplicates" do
    test "an original and its offsite copy raise no candidate", %{letter: letter} do
      bytes = StorageFixtures.png("the same bytes")
      stored!(letter.id, bytes: bytes)
      stored!(letter.id, bytes: bytes, roles: [redundant: "offsite-copy"])

      Dedup.detect()

      assert Dedup.involving(letter.id) == []
    end

    test "the same bytes under two holdings do", %{letter: letter, manifestation: manifestation} do
      {:ok, %{digital_item: other}} = Catalog.create_digital_item(manifestation.id, "copy")
      bytes = StorageFixtures.png("the same bytes")
      stored!(letter.id, bytes: bytes)
      stored!(other.id, bytes: bytes)

      assert Dedup.detect() >= 1
      assert [%{signal: :digest}] = Dedup.involving(letter.id)
    end
  end

  describe "12. Deduplication proposes and never merges; a decision survives the next run" do
    setup %{letter: letter, manifestation: manifestation} do
      {:ok, %{digital_item: other}} = Catalog.create_digital_item(manifestation.id, "copy")
      bytes = StorageFixtures.png("the same bytes")
      one = stored!(letter.id, bytes: bytes)
      two = stored!(other.id, bytes: bytes)
      %{other: other, one: one, two: two}
    end

    test "detection changes nothing but the candidate list", %{letter: letter, other: other} do
      assets_before = Repo.aggregate(Asset, :count)

      Dedup.detect()

      assert Repo.aggregate(Asset, :count) == assets_before
      assert [_] = Catalog.assets_of(letter.id)
      assert [_] = Catalog.assets_of(other.id)
    end

    test "a pair judged distinct stays judged on the next run", %{letter: letter, principal: p} do
      Dedup.detect()
      [candidate] = Dedup.involving(letter.id)
      {:ok, _} = Dedup.decide(candidate.id, :distinct, p.id)

      assert Dedup.detect() == 0

      assert [%{decision: :distinct}] = Dedup.involving(letter.id)
      assert Dedup.open() == []
    end
  end

  describe "12, from a member. A pair no signal found is proposed and decided by a person" do
    setup %{letter: letter, principal: principal} do
      {:ok, %{work: rescan_work, expression: rescan_expression, manifestation: rescan}} =
        Catalog.create_work("Letter from Ada, rescanned")

      {:ok, %{digital_item: rescan_item}} =
        Catalog.create_digital_item(rescan.id, "Letter from Ada, rescanned")

      stored!(letter.id, bytes: StorageFixtures.png("first scan"))
      stored!(rescan_item.id, bytes: StorageFixtures.png("second scan"))

      {:ok, candidate} = Dedup.propose(rescan_item.id, letter.id, principal.id)

      %{
        candidate: candidate,
        rescan: rescan,
        rescan_work: rescan_work,
        rescan_expression: rescan_expression
      }
    end

    test "detection finds nothing, and the proposal names who raised it", context do
      assert Dedup.detect() == 0
      assert context.candidate.signal == :member
      assert context.candidate.raised_by == context.principal.id
    end

    test "a member's candidate with no member named is refused by the database", context do
      now = DateTime.utc_now()
      [left_id, right_id] = Enum.sort([context.letter.id, context.manifestation.id])

      assert_raise Postgrex.Error, ~r/a_member_candidate_names_its_member/, fn ->
        Repo.insert_all("duplicate_candidates", [
          %{
            id: Ecto.UUID.dump!(UUIDv7.generate()),
            left_id: Ecto.UUID.dump!(left_id),
            right_id: Ecto.UUID.dump!(right_id),
            signal: "member",
            detected_at: now,
            inserted_at: now,
            updated_at: now
          }
        ])
      end
    end

    test "same expression moves the rescan under the first and recycles what it emptied",
         context do
      [first_expression] = Catalog.expressions_in(context.manifestation.id)

      assert {:ok, %{decision: :same_expression}} =
               Dedup.decide(context.candidate.id, :same_expression, context.principal.id)

      assert [%{id: moved_under}] = Catalog.expressions_in(context.rescan.id)
      assert moved_under == first_expression.id
      assert [_, _] = Catalog.manifestations_of(first_expression.id)

      assert {:recycled, _, recycling} = Lifecycle.state(context.rescan_work.id)
      assert context.rescan_expression.id in Lifecycle.contents(recycling.id)
      assert {:live, _} = Lifecycle.state(context.rescan.id)
    end

    test "a work with another expression keeps it, and only the emptied one goes", context do
      {:ok, %{expression: reading}} =
        Catalog.add_expression(context.rescan_work.id, "Letter from Ada, read aloud")

      {:ok, _} = Dedup.decide(context.candidate.id, :same_expression, context.principal.id)

      assert {:live, _} = Lifecycle.state(context.rescan_work.id)
      assert {:live, _} = Lifecycle.state(reading.id)
      assert {:recycled, _, _} = Lifecycle.state(context.rescan_expression.id)
    end

    test "same work keeps both expressions and recycles only the work they left",
         context do
      [first_expression] = Catalog.expressions_in(context.manifestation.id)

      assert {:ok, %{decision: :same_work}} =
               Dedup.decide(context.candidate.id, :same_work, context.principal.id)

      # spec-03 §8.3's level above *same expression*: one work, two realizations of
      # it. A live take and a studio take of one song stand in this relation, and so
      # do two dumps of one game (spec-04 §6.9, criterion 40).
      assert {:live, _} = Lifecycle.state(context.rescan_expression.id)
      assert {:live, _} = Lifecycle.state(first_expression.id)
      assert [%{id: still_its_own}] = Catalog.expressions_in(context.rescan.id)
      assert still_its_own == context.rescan_expression.id

      realizing = context.manifestation.id |> works_of() |> hd()
      assert works_of(context.rescan.id) == [realizing]

      assert [_, _] = Catalog.expressions_of(realizing)
      assert {:recycled, _, _} = Lifecycle.state(context.rescan_work.id)
    end

    test "same work leaves a work that still realizes something alone", context do
      {:ok, %{expression: reading}} =
        Catalog.add_expression(context.rescan_work.id, "Letter from Ada, read aloud")

      {:ok, _} = Dedup.decide(context.candidate.id, :same_work, context.principal.id)

      assert {:live, _} = Lifecycle.state(context.rescan_work.id)
      assert {:live, _} = Lifecycle.state(reading.id)
      assert {:live, _} = Lifecycle.state(context.rescan_expression.id)
    end
  end

  describe "14. A pair decided distinct is not raised again, by a detection run or by matching" do
    setup %{letter: letter, manifestation: manifestation} do
      {:ok, %{digital_item: other}} = Catalog.create_digital_item(manifestation.id, "copy")
      bytes = StorageFixtures.png("the same bytes")
      stored!(letter.id, bytes: bytes)
      stored!(other.id, bytes: bytes)

      # The same pair under two of §8.2's signals: identical bytes, and one
      # external identifier carried by both, which spec-01 §4.3 tolerates. Before
      # the pair became the key, deciding under one of them left the other free to
      # raise it again.
      for res_id <- [letter.id, other.id] do
        {:ok, _} =
          Catalog.create_nomen(%{
            res_id: res_id,
            nomen_string: "urn:example:letter-1943-04-12",
            scheme: "example"
          })
      end

      %{other: other}
    end

    test "two signals raise one row, not one each", %{letter: letter} do
      Dedup.detect()

      assert [%{signal: :digest}] = Dedup.involving(letter.id)
    end

    test "a later run does not raise it again under the other signal",
         %{letter: letter, principal: principal} do
      Dedup.detect()
      [candidate] = Dedup.involving(letter.id)
      {:ok, _} = Dedup.decide(candidate.id, :distinct, principal.id)

      assert Dedup.detect() == 0
      assert [%{decision: :distinct}] = Dedup.involving(letter.id)
      assert Dedup.open() == []
    end

    test "a member proposing a decided pair is refused with the decision it carries",
         %{letter: letter, other: other, principal: principal} do
      Dedup.detect()
      [candidate] = Dedup.involving(letter.id)
      {:ok, _} = Dedup.decide(candidate.id, :distinct, principal.id)

      assert Dedup.propose(other.id, letter.id, principal.id) ==
               {:error, {:already_decided, :distinct}}
    end

    test "a member proposing an undecided pair is given the row it already has",
         %{letter: letter, other: other, principal: principal} do
      Dedup.detect()
      [%{id: raised}] = Dedup.involving(letter.id)

      assert {:ok, %{id: ^raised}} = Dedup.propose(other.id, letter.id, principal.id)
      assert [_one] = Dedup.involving(letter.id)
    end

    test "the store refuses a second row for one pair", %{letter: letter, other: other} do
      now = DateTime.utc_now()
      [left_id, right_id] = Enum.sort([letter.id, other.id])

      Dedup.detect()

      assert_raise Postgrex.Error, ~r/duplicate_candidates_left_id_right_id_index/, fn ->
        Repo.insert_all("duplicate_candidates", [
          %{
            id: Ecto.UUID.dump!(UUIDv7.generate()),
            left_id: Ecto.UUID.dump!(left_id),
            right_id: Ecto.UUID.dump!(right_id),
            signal: "perceptual",
            detected_at: now,
            inserted_at: now,
            updated_at: now
          }
        ])
      end
    end
  end

  defp works_of(manifestation_id) do
    manifestation_id
    |> Catalog.expressions_in()
    |> Enum.map(& &1.work_id)
    |> Enum.uniq()
  end

  defp attrs(overrides \\ []) do
    file_name = Keyword.get(overrides, :file_name, "1943-04-12.tiff")
    bytes = Keyword.get(overrides, :bytes, StorageFixtures.png("#{System.unique_integer()}"))

    roles =
      Enum.map(Keyword.get(overrides, :roles, acquired: "original-scan"), fn {class, role} ->
        %{role_class: class, role: role}
      end)

    %{
      location: StorageFixtures.stored!(file_name, bytes),
      essence: Keyword.get(overrides, :essence, :lossless),
      part_sequence: Keyword.get(overrides, :part_sequence),
      verification_interval_seconds: 90 * 86_400,
      roles: roles
    }
  end

  defp store(digital_item_id, overrides) do
    Catalog.create_asset(digital_item_id, attrs(overrides), "1943-04-12.tiff")
  end

  defp stored!(digital_item_id, overrides \\ []) do
    {:ok, %{asset: asset}} = store(digital_item_id, overrides)
    asset
  end

  defp derivation!(tool, version, input_id) do
    {:ok, derivation} =
      Annotations.record_derivation(%{
        tool: tool,
        version: version,
        input_id: input_id,
        parameters: %{},
        derived_at: DateTime.utc_now()
      })

    derivation
  end

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

  defp ids(rows), do: Enum.map(rows, & &1.id)
end
