defmodule Pluteus.WorkersTest do
  @moduledoc """
  The scheduled work spec-03 §5.2 and spec-01 §14.1 require: verification that
  runs without anyone deciding to run it, and a recycle-bin window that closes
  on its own.
  """

  use Pluteus.DataCase, async: true
  use Oban.Testing, repo: Pluteus.Repo

  alias Pluteus.Assets
  alias Pluteus.Catalog
  alias Pluteus.Lifecycle
  alias Pluteus.Principals
  alias Pluteus.Storage
  alias Pluteus.Workers.PurgeExpired
  alias Pluteus.Workers.ScheduleVerification
  alias Pluteus.Workers.VerifyAsset

  setup do
    {:ok, principal} = Principals.create_principal(%{role: "member"})
    %{principal: principal}
  end

  describe "verifying one asset" do
    test "intact bytes are recorded as verified" do
      asset = a_letter_on_disk()

      assert :ok = perform_job(VerifyAsset, %{asset_id: asset.id})

      assert [%{outcome: :verified}] = Assets.verifications_of(asset.id)
      refute asset.id in ids(Assets.unverified())
    end

    test "altered bytes are recorded as a mismatch and left as they are" do
      asset = a_letter_on_disk()
      :ok = Storage.put(asset.location, "not the letter")

      assert :ok = perform_job(VerifyAsset, %{asset_id: asset.id})

      assert [%{outcome: :mismatched}] = Assets.verifications_of(asset.id)
      assert Storage.read(asset.location) == "not the letter"
      assert asset.id in ids(Assets.unverified())
    end

    test "missing bytes are recorded as unreadable" do
      asset = a_letter_on_disk()
      :ok = Storage.delete(asset.location)

      assert :ok = perform_job(VerifyAsset, %{asset_id: asset.id})

      assert [%{outcome: :unreadable}] = Assets.verifications_of(asset.id)
    end

    test "an asset in the recycle bin is still checked", %{principal: principal} do
      asset = a_letter_on_disk()
      {:ok, _} = Lifecycle.recycle(asset.id, principal.id)

      assert :ok = perform_job(VerifyAsset, %{asset_id: asset.id})

      assert [%{outcome: :verified}] = Assets.verifications_of(asset.id)
    end

    test "an asset purged before its turn is cancelled, not failed", %{principal: principal} do
      asset = a_letter_on_disk()
      {:ok, recycling} = Lifecycle.recycle(asset.id, principal.id)
      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())

      assert {:cancel, :purged_before_verification} =
               perform_job(VerifyAsset, %{asset_id: asset.id})
    end

    test "a digest in an algorithm nothing can compute is a defect, and raises" do
      asset = a_letter_on_disk(%{digest_algorithm: "md4-of-my-own-devising"})

      assert_raise ArgumentError, fn -> Assets.verify(asset.id) end
    end
  end

  describe "scheduling verification" do
    test "every asset not known to be intact gets a job" do
      due = a_letter_on_disk()
      fresh = a_letter_on_disk()
      {:ok, _} = Assets.record_verification(fresh.id, :verified)

      assert :ok = perform_job(ScheduleVerification, %{})

      queued = Enum.map(all_enqueued(worker: VerifyAsset), & &1.args["asset_id"])

      assert due.id in queued
      refute fresh.id in queued
    end

    test "running the schedule twice does not queue an asset twice" do
      asset = a_letter_on_disk()

      :ok = perform_job(ScheduleVerification, %{})
      :ok = perform_job(ScheduleVerification, %{})

      assert [_one] =
               Enum.filter(
                 all_enqueued(worker: VerifyAsset),
                 &(&1.args["asset_id"] == asset.id)
               )
    end

    test "the schedule runs on its own, hourly, and the purge daily" do
      crontab = Application.fetch_env!(:pluteus, Oban)[:cron][:crontab]

      assert {"0 * * * *", ScheduleVerification} in crontab
      assert {"0 3 * * *", PurgeExpired} in crontab
    end
  end

  describe "closing the recycle-bin window" do
    test "a deletion past its window is purged", %{principal: principal} do
      {:ok, %{work: work}} = Catalog.create_work("The Dig")
      long_ago = DateTime.add(DateTime.utc_now(), -31 * 86_400, :second)
      {:ok, _} = Lifecycle.recycle(work.id, principal.id, now: long_ago)

      assert :ok = perform_job(PurgeExpired, %{})

      assert {:purged, _res, _tombstone} = Lifecycle.state(work.id)
    end

    test "bytes it could not remove are the job's error", %{principal: principal} do
      asset = a_letter_on_disk()
      :ok = Storage.delete(asset.location)
      long_ago = DateTime.add(DateTime.utc_now(), -31 * 86_400, :second)
      {:ok, _} = Lifecycle.recycle(asset.id, principal.id, now: long_ago)

      assert {:error, {:bytes_not_removed, [{location, :enoent}]}} =
               perform_job(PurgeExpired, %{})

      assert location == asset.location
      assert {:purged, _res, _tombstone} = Lifecycle.state(asset.id)
    end
  end

  defp ids(assets), do: Enum.map(assets, & &1.id)

  defp a_letter_on_disk(overrides \\ %{}) do
    {:ok, %{manifestation: manifestation}} =
      Catalog.create_work("Letter from Ada, 12 April 1943")

    {:ok, %{digital_item: digital_item}} =
      Catalog.create_digital_item(manifestation.id, "Letter from Ada, 12 April 1943")

    bytes = :crypto.strong_rand_bytes(4096)
    location = "letters/#{System.unique_integer([:positive])}/1943-04-12.tiff"
    :ok = Storage.put(location, bytes)
    on_exit(fn -> Storage.delete(location) end)

    attrs =
      Map.merge(
        %{
          location: location,
          size: byte_size(bytes),
          digest: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower),
          digest_algorithm: "sha-256",
          format: "fmt/353",
          essence: :lossless,
          verification_interval_seconds: 90 * 86_400,
          roles: [%{role_class: :acquired, role: "original-scan"}]
        },
        overrides
      )

    {:ok, %{asset: asset}} = Catalog.create_asset(digital_item.id, attrs, "1943-04-12.tiff")
    asset
  end
end
