defmodule Pluteus.Presentation.AssetTest do
  @moduledoc """
  The presentation asset store ([spec-10] §11.1 and §11.6): what a row asserts,
  where its bytes lie, and that purging a holding takes its derivatives with it.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Ingest
  alias Pluteus.Lifecycle
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Asset
  alias Pluteus.Principals
  alias Pluteus.Storage
  alias Pluteus.StorageFixtures

  setup do
    actor = Principals.system!()

    {:ok, %{manifestation: manifestation}} = Catalog.create_work("Kind of Blue")
    {:ok, %{digital_item: item}} = Catalog.create_digital_item(manifestation.id, "the file")

    location = StorageFixtures.stored!("source.png", StorageFixtures.png("a source"))

    {:ok, %{asset: source}} =
      Catalog.create_asset(
        item.id,
        %{
          location: location,
          essence: :lossless,
          verification_interval_seconds: 86_400,
          roles: [%{role_class: :acquired, role: "original"}]
        },
        "source.png"
      )

    %{actor: actor, manifestation: manifestation, item: item, source: source}
  end

  defp record!(context, overrides \\ %{}) do
    subject_id = overrides[:subject_id] || context.manifestation.id
    profile = overrides[:profile] || "image-320"
    ordinal = Map.get(overrides, :ordinal, 0)

    location = Presentation.location_for(subject_id, profile, ordinal, "webp")
    bytes = overrides[:bytes] || StorageFixtures.png("#{profile}/#{ordinal}")
    :ok = Storage.put(location, bytes)
    on_exit(fn -> Storage.delete(location) end)

    attrs =
      Map.merge(
        %{
          subject_id: subject_id,
          profile: profile,
          ordinal: ordinal,
          location: location,
          media_type: "image/webp",
          size: byte_size(bytes),
          digest: "sha256:#{Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)}",
          digest_algorithm: "sha256",
          width: 320,
          height: 240,
          descriptor: %{"width" => 320},
          source_asset_id: context.source.id,
          source_digest: context.source.digest,
          generated_at: DateTime.utc_now(),
          last_served_at: DateTime.utc_now()
        },
        Map.drop(overrides, [:bytes])
      )

    {:ok, recorded} = Presentation.record(attrs)
    recorded
  end

  describe "a row asserts what the bytes are, and only where they exist" do
    test "an artefact is found by subject and profile", context do
      recorded = record!(context)

      found = Presentation.get(context.manifestation.id, "image-320")

      assert found.location == recorded.location
      assert found.media_type == "image/webp"
      assert found.width == 320
      assert found.height == 240
      assert Storage.exists?(found.location)
    end

    test "a profile nobody asked for is absent rather than empty", context do
      record!(context)

      assert Presentation.get(context.manifestation.id, "image-2048") == nil
    end

    test "there is no state column: absence is the absence of a row" do
      refute :state in Asset.__schema__(:fields)
      refute :generating in Asset.__schema__(:fields)
    end

    test "regenerating replaces the row rather than accumulating", context do
      first = record!(context)
      second = record!(context, %{bytes: StorageFixtures.png("regenerated")})

      assert second.location == first.location
      assert [_] = Presentation.for_subject(context.manifestation.id)
      refute second.digest == first.digest
    end

    test "several profiles and several ordinals of one subject coexist", context do
      record!(context, %{profile: "image-320"})
      record!(context, %{profile: "image-640"})
      record!(context, %{profile: "trickplay-320", ordinal: 0})
      record!(context, %{profile: "trickplay-320", ordinal: 1})

      assert [_, _, _, _] = Presentation.for_subject(context.manifestation.id)
      assert Presentation.get(context.manifestation.id, "trickplay-320", 1).ordinal == 1
    end
  end

  describe "§11.1's closed set is the registry's, not the schema's" do
    test "a profile the registry does not name is refused", context do
      location = Presentation.location_for(context.manifestation.id, "image-999", 0, "webp")

      assert {:error, changeset} =
               Presentation.record(%{
                 subject_id: context.manifestation.id,
                 profile: "image-999",
                 location: location,
                 media_type: "image/webp",
                 size: 10,
                 digest: "sha256:abc",
                 digest_algorithm: "sha256",
                 source_asset_id: context.source.id,
                 source_digest: context.source.digest,
                 generated_at: DateTime.utc_now(),
                 last_served_at: DateTime.utc_now()
               })

      assert %{profile: [message]} = errors_on(changeset)
      assert message =~ "image-999"
    end

    test "every profile the registry names is accepted", context do
      for profile <- Pluteus.Presentation.Registry.profile_names() do
        assert %Asset{} = record!(context, %{profile: profile})
      end
    end
  end

  describe "a geometry states both dimensions or neither" do
    test "an artefact with no pixels carries no geometry", context do
      recorded =
        record!(context, %{profile: "waveform-overview-1000", width: nil, height: nil})

      assert recorded.width == nil
      assert recorded.height == nil
    end

    test "half a geometry is refused, and the message names the pair", context do
      assert {:error, changeset} =
               Presentation.record(%{
                 subject_id: context.manifestation.id,
                 profile: "image-320",
                 location: "presentation/aa/bb/half.webp",
                 media_type: "image/webp",
                 size: 10,
                 digest: "sha256:abc",
                 digest_algorithm: "sha256",
                 width: 320,
                 source_asset_id: context.source.id,
                 source_digest: context.source.digest,
                 generated_at: DateTime.utc_now(),
                 last_served_at: DateTime.utc_now()
               })

      assert %{width: ["a geometry states both dimensions or neither"]} = errors_on(changeset)
    end
  end

  describe "bytes lie outside the holdings layout" do
    test "a presentation location is one segment deeper than a holding's", context do
      location = Presentation.location_for(context.manifestation.id, "image-320", 0, "webp")

      assert ["presentation", shard, sub, file] = Path.split(location)
      assert String.length(shard) == 2
      assert String.length(sub) == 2
      assert file =~ "image-320"

      assert [_shard, _sub, _file] = Path.split(Ingest.location_for(context.manifestation.id))
    end

    test "a cache fill is never reported as unaccounted bytes", context do
      record!(context)

      Ingest.find_stray_bytes()

      locations = Enum.map(Ingest.open_findings(), & &1.location)
      refute Enum.any?(locations, &String.starts_with?(&1 || "", "presentation/"))
    end
  end

  describe "staleness is detectable from the source's digest" do
    test "an artefact drawn from the bytes that are still there is current", context do
      recorded = record!(context)

      assert Presentation.current?(recorded, context.source.digest)
      refute Presentation.current?(recorded, "sha256:something-else")
    end
  end

  describe "serving reorders the eviction queue and reading does not" do
    test "a lookup leaves the order alone", context do
      recorded = record!(context)

      _read = Presentation.get(context.manifestation.id, "image-320")

      assert Presentation.get(context.manifestation.id, "image-320").last_served_at ==
               recorded.last_served_at
    end

    test "serving moves it to the back", context do
      recorded = record!(context)
      later = DateTime.add(recorded.last_served_at, 60, :second)

      {:ok, served} = Presentation.serve(recorded, later)

      assert DateTime.compare(served.last_served_at, recorded.last_served_at) == :gt
    end
  end

  describe "discarding takes the row and the bytes" do
    test "one artefact goes", context do
      recorded = record!(context)

      assert :ok = Presentation.discard(recorded)

      assert Presentation.get(context.manifestation.id, "image-320") == nil
      refute Storage.exists?(recorded.location)
    end

    test "purging a holding takes its derivatives with it", context do
      recorded = record!(context)

      {:ok, recycling} = Lifecycle.recycle(context.item.id, context.actor.id)
      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())

      assert Presentation.get(context.manifestation.id, "image-320") == nil
      refute Storage.exists?(recorded.location)
    end
  end

  describe "many subjects are answered in one call" do
    test "a page of tiles costs one query", context do
      {:ok, %{manifestation: other}} = Catalog.create_work("Sketches of Spain")

      record!(context, %{profile: "image-320"})
      record!(context, %{subject_id: other.id, profile: "image-320"})

      found =
        Presentation.for_subjects(
          [context.manifestation.id, other.id, Ecto.UUID.generate()],
          "image-320"
        )

      assert map_size(found) == 2
      assert found[context.manifestation.id].subject_id == context.manifestation.id
      assert found[other.id].subject_id == other.id
    end

    test "no subjects is no query and no rows" do
      assert Presentation.for_subjects([], "image-320") == %{}
    end
  end
end
