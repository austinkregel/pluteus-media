defmodule Pluteus.Ingest.StrayBytesTest do
  @moduledoc """
  spec-04 §4.3: bytes under primary storage whose identifier has no record.

  The pass reads the whole of primary storage, which every other test writes
  into, so this module runs alone.
  """

  use Pluteus.DataCase, async: false

  alias Pluteus.Catalog
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Storage
  alias Pluteus.StorageFixtures

  test "a pass over more stray bytes than one statement can carry still completes" do
    # The wire protocol carries 65535 parameters and a finding spends nine, so a single
    # insert fails somewhere past seven thousand files. A deployment with that many
    # stray files is precisely the one whose operator needs the report, and before this
    # was batched the pass crashed every night for exactly that reason.
    locations =
      for _ <- 1..7_400 do
        location = Ingest.location_for(UUIDv7.generate())
        :ok = Storage.put(location, "x")
        location
      end

    on_exit(fn -> for location <- locations, do: Storage.delete(location) end)

    assert Ingest.find_stray_bytes() >= 7_400
  end

  test "stray bytes are a finding, recorded once, and nothing is deleted" do
    id = UUIDv7.generate()
    location = Ingest.location_for(id)
    :ok = Storage.put(location, "bytes no record accounts for")
    on_exit(fn -> Storage.delete(location) end)

    Ingest.find_stray_bytes()
    Ingest.find_stray_bytes()

    assert [%{stage: :acquire, kind: "bytes_without_a_record", permanent: true}] =
             Enum.filter(Ingest.open_findings(), &(&1.location == location))

    assert Storage.read(location) == "bytes no record accounts for"
  end

  test "bytes an acquisition accounts for are not stray" do
    id = UUIDv7.generate()
    location = Ingest.location_for(id)
    :ok = Storage.put(location, "accounted for")
    on_exit(fn -> Storage.delete(location) end)

    %{id: id, inbox_path: "so-what.flac", location: location}
    |> Acquisition.recorded_changeset()
    |> Repo.insert!()

    Ingest.find_stray_bytes()

    refute Enum.any?(Ingest.open_findings(), &(&1.location == location))
  end

  test "bytes an asset accounts for are not stray" do
    {:ok, %{manifestation: manifestation}} = Catalog.create_work("Letter from Ada")
    {:ok, %{digital_item: letter}} = Catalog.create_digital_item(manifestation.id, "Letter")
    location = Ingest.location_for(UUIDv7.generate())
    :ok = Storage.put(location, StorageFixtures.png("an asset's own bytes"))
    on_exit(fn -> Storage.delete(location) end)

    {:ok, _} =
      Catalog.create_asset(
        letter.id,
        %{
          location: location,
          essence: :lossless,
          verification_interval_seconds: 86_400,
          roles: [%{role_class: :acquired, role: "original-scan"}]
        },
        "letter.png"
      )

    Ingest.find_stray_bytes()

    refute Enum.any?(Ingest.open_findings(), &(&1.location == location))
  end
end
