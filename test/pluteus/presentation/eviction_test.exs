defmodule Pluteus.Presentation.EvictionTest do
  @moduledoc """
  [spec-10] §11.6's bounded eviction, and criterion 45: a presentation asset's
  eviction is observable as having run.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Ingest
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Eviction
  alias Pluteus.Presentation.EvictionRun
  alias Pluteus.Principals
  alias Pluteus.Storage
  alias Pluteus.StorageFixtures

  @now ~U[2026-09-25 12:00:00.000000Z]

  setup do
    _system = Principals.system!()

    {:ok, %{manifestation: manifestation}} = Catalog.create_work("Kind of Blue")
    {:ok, %{digital_item: item}} = Catalog.create_digital_item(manifestation.id, "the file")

    {:ok, %{asset: source}} =
      Catalog.create_asset(
        item.id,
        %{
          location: StorageFixtures.stored!("source.png", StorageFixtures.png("a source")),
          essence: :lossless,
          verification_interval_seconds: 86_400,
          roles: [%{role_class: :acquired, role: "original"}]
        },
        "source.png"
      )

    %{manifestation: manifestation, source: source}
  end

  defp held!(context, profile, opts) do
    subject_id = Keyword.get(opts, :subject_id, context.manifestation.id)
    size = Keyword.get(opts, :size, 100)
    served_at = Keyword.get(opts, :served_at, @now)

    location = Presentation.location_for(subject_id, profile, 0, "jpg")
    :ok = Storage.put(location, :binary.copy("x", size))
    on_exit(fn -> Storage.delete(location) end)

    {:ok, held} =
      Presentation.record(%{
        subject_id: subject_id,
        profile: profile,
        location: location,
        media_type: "image/jpeg",
        size: size,
        digest: "sha256:#{profile}",
        digest_algorithm: "sha256",
        width: 320,
        height: 240,
        source_asset_id: context.source.id,
        source_digest: context.source.digest,
        generated_at: served_at,
        last_served_at: served_at
      })

    held
  end

  describe "45. An eviction is observable as having run" do
    test "a pass writes a row saying what it did", context do
      held!(context, "image-320", [])

      counted = Eviction.run(@now)

      assert [run] = Repo.all(EvictionRun)
      assert run.started_at
      assert run.finished_at
      assert run.considered == 1
      assert run.evicted == counted.evicted
      assert run.bytes_reclaimed == counted.bytes_reclaimed
    end

    test "a pass that evicted nothing still says it ran", context do
      held!(context, "image-320", [])

      Eviction.run(@now)

      assert [%{evicted: 0, bytes_reclaimed: 0, considered: 1}] = Repo.all(EvictionRun)
    end

    test "a run with no finish is an unfinished run, not an absent one" do
      {:ok, _} =
        Repo.insert(EvictionRun.started_changeset(%{started_at: DateTime.add(@now, -7_201)}))

      # A pass that crashed halfway is visible as this rather than inferred from a
      # disk filling up.
      assert [%{finished_at: nil}] = Repo.all(EvictionRun)
      assert Eviction.overdue?(@now)
    end

    test "a pass exactly at twice its period is not yet overdue" do
      {:ok, _} =
        Repo.insert(EvictionRun.started_changeset(%{started_at: DateTime.add(@now, -7_200)}))

      # The window is a bound the run has to exceed, not reach.
      refute Eviction.overdue?(@now)
    end

    test "a pass that has not run within twice its period is overdue" do
      {:ok, _} =
        Repo.insert(EvictionRun.started_changeset(%{started_at: DateTime.add(@now, -100_000)}))

      assert Eviction.overdue?(@now)
    end

    test "a pass that finished recently is not overdue", context do
      held!(context, "image-320", [])
      Eviction.run(@now)

      refute Eviction.overdue?(@now)
    end

    test "no pass having ever run is not itself overdue" do
      # Nothing to report before the first pass; a deployment that has never needed
      # one has nothing wrong with it.
      refute Eviction.overdue?(@now)
    end

    test "an overdue pass reaches a person as a finding" do
      {:ok, _} =
        Repo.insert(EvictionRun.started_changeset(%{started_at: DateTime.add(@now, -100_000)}))

      :ok = Eviction.report_if_overdue(@now)

      assert Enum.any?(
               Ingest.open_findings(),
               &(&1.kind == "presentation_eviction_overdue")
             )
    end
  end

  describe "the bound is age and size at once" do
    test "an artefact nobody has asked for in the idle period goes", context do
      stale = held!(context, "image-320", served_at: DateTime.add(@now, -7200))
      fresh = held!(context, "image-640", served_at: @now)

      Eviction.run(@now)

      assert Presentation.get(context.manifestation.id, "image-320") == nil
      refute Storage.exists?(stale.location)

      assert Presentation.get(context.manifestation.id, "image-640")
      assert Storage.exists?(fresh.location)
    end

    test "beyond the ceiling the least recently served go first", context do
      {:ok, %{manifestation: second}} = Catalog.create_work("Sketches of Spain")
      {:ok, %{manifestation: third}} = Catalog.create_work("Porgy and Bess")

      # The test ceiling is 10,000 bytes. Three of 6,000 are over it by two.
      oldest = held!(context, "image-320", size: 6_000, served_at: DateTime.add(@now, -600))

      middle =
        held!(context, "image-320",
          size: 6_000,
          served_at: DateTime.add(@now, -300),
          subject_id: second.id
        )

      newest = held!(context, "image-320", size: 6_000, served_at: @now, subject_id: third.id)

      Eviction.run(@now)

      refute Storage.exists?(oldest.location)
      refute Storage.exists?(middle.location)
      assert Storage.exists?(newest.location)
    end

    test "under the ceiling and inside the idle period, nothing goes", context do
      held = held!(context, "image-320", size: 100, served_at: @now)

      assert %{evicted: 0} = Eviction.run(@now)
      assert Storage.exists?(held.location)
    end
  end

  describe "nothing is exempt" do
    test "a profile the registry generates at ingest is evicted like any other",
         context do
      at_ingest = Presentation.Registry.generated_at_ingest()

      assert "image-160" in at_ingest

      held = held!(context, "image-160", served_at: DateTime.add(@now, -7200))

      Eviction.run(@now)

      # An exemption would be an unbounded set. This returns on the next pass over
      # the holdings that need it.
      assert Presentation.get(context.manifestation.id, "image-160") == nil
      refute Storage.exists?(held.location)
    end

    test "eviction never touches the holding it was drawn from", context do
      held!(context, "image-320", served_at: DateTime.add(@now, -7200))

      Eviction.run(@now)

      assert Storage.exists?(context.source.location)
      assert Repo.get(Pluteus.Catalog.Asset, context.source.id)
    end
  end
end
