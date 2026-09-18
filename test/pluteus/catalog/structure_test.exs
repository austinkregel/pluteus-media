defmodule Pluteus.Catalog.StructureTest do
  @moduledoc """
  Stream addressing (spec-01 §8.5) and manifestation whole-part (spec-01 §12.1,
  §14.3).
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.ManifestationPart
  alias Pluteus.Lifecycle

  describe "§8.5, a track selector names one stream of a container" do
    setup do
      {:ok, %{expression: expression, manifestation: film}} = Catalog.create_work("Stalker")
      %{expression: expression, film: film}
    end

    test "it is accepted at manifestation and refused at expression", context do
      assert {:ok, %{address: %Address{selector_type: :track}}} =
               Catalog.create_address(context.film.id, russian_stereo())

      assert {:error, :address, changeset, _} =
               Catalog.create_address(context.expression.id, russian_stereo())

      assert "a track selector is not valid against a expression" in errors_on(changeset).target_kind
    end

    test "a region of one stream is addressed on its track address", context do
      {:ok, %{address: russian}} = Catalog.create_address(context.film.id, russian_stereo())

      assert {:ok, %{address: region}} =
               Catalog.create_address(russian.id, %{
                 selector_type: :temporal,
                 start_ms: 60_000,
                 end_ms: 90_000
               })

      assert region.target_id == russian.id
    end

    test "a region is refused on an address that is not a track", context do
      {:ok, %{address: page}} =
        Catalog.create_address(context.film.id, %{
          selector_type: :spatial,
          x_percent: 0.0,
          y_percent: 0.0,
          width_percent: 50.0,
          height_percent: 50.0
        })

      assert {:error, :address, changeset, _} =
               Catalog.create_address(page.id, %{
                 selector_type: :temporal,
                 start_ms: 0,
                 end_ms: 1_000
               })

      assert %{target_id: [_]} = errors_on(changeset)
    end

    test "a stream is never named by its index, its codec or its layout's name" do
      fields = Address.__schema__(:fields)

      for unstable <- ["index", "codec", "layout"] do
        refute Enum.any?(fields, &(&1 |> Atom.to_string() |> String.contains?(unstable)))
      end
    end

    test "one stream has one address, whatever order its disposition flags came in", context do
      {:ok, _} =
        Catalog.create_address(
          context.film.id,
          %{russian_stereo() | stream_disposition: ["default", "original"]}
        )

      assert {:error, :address, changeset, _} =
               Catalog.create_address(
                 context.film.id,
                 %{russian_stereo() | stream_disposition: ["original", "default", "original"]}
               )

      assert %{target_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "two streams alike in everything else are told apart by ordinal", context do
      {:ok, _} = Catalog.create_address(context.film.id, russian_stereo())

      assert {:ok, %{address: %Address{stream_ordinal: 2}}} =
               Catalog.create_address(context.film.id, %{russian_stereo() | stream_ordinal: 2})
    end

    test "a stream with no language is still one stream", context do
      unlabelled = %{russian_stereo() | stream_language: nil}

      {:ok, _} = Catalog.create_address(context.film.id, unlabelled)

      assert {:error, :address, _changeset, _} =
               Catalog.create_address(context.film.id, unlabelled)
    end
  end

  describe "§12.1, a released aggregate's order is its whole-part positions" do
    setup do
      release = manifestation!("Kind of Blue")
      medium = manifestation!("Kind of Blue, disc 1")
      so_what = manifestation!("So What")
      freddie = manifestation!("Freddie Freeloader")

      {:ok, _} = Catalog.add_manifestation_part(release.id, medium.id, 1)
      {:ok, _} = Catalog.add_manifestation_part(medium.id, so_what.id, 1)
      {:ok, _} = Catalog.add_manifestation_part(medium.id, freddie.id, 2)

      %{release: release, medium: medium, so_what: so_what, freddie: freddie}
    end

    test "parts come back in position order", context do
      assert [%{part_id: first, position: 1}, %{part_id: second, position: 2}] =
               Catalog.parts_of(context.medium.id)

      assert first == context.so_what.id
      assert second == context.freddie.id
    end

    test "two parts at one position are refused at commit", context do
      blue_in_green = manifestation!("Blue in Green")

      assert_raise Postgrex.Error, ~r/one_part_per_position/, fn ->
        Repo.transaction(fn ->
          {:ok, _} = Catalog.add_manifestation_part(context.medium.id, blue_in_green.id, 2)
          Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")
        end)
      end
    end

    test "swapping two positions is one grouped update", context do
      {:ok, _} =
        Repo.transaction(fn ->
          for {part, position} <- [{context.so_what, 2}, {context.freddie, 1}] do
            Repo.update_all(
              from(p in ManifestationPart,
                where: p.whole_id == ^context.medium.id and p.part_id == ^part.id
              ),
              set: [position: position]
            )
          end
        end)

      assert [%{part_id: first}, _] = Catalog.parts_of(context.medium.id)
      assert first == context.freddie.id
    end

    test "a manifestation is not its own part", context do
      assert {:error, changeset} =
               Catalog.add_manifestation_part(context.medium.id, context.medium.id, 3)

      assert %{part_id: [_]} = errors_on(changeset)
    end
  end

  describe "§14.3, manifestation whole-part does not cascade" do
    test "recycling a release leaves its track; purge removes only the link", %{actor: actor} do
      release = manifestation!("Kind of Blue")
      track = manifestation!("So What")
      {:ok, _} = Catalog.add_manifestation_part(release.id, track.id, 1)

      {:ok, recycling} = Lifecycle.recycle(release.id, actor.id)

      refute track.id in Lifecycle.contents(recycling.id)

      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())

      assert {:live, _} = Lifecycle.state(track.id)
      assert Catalog.wholes_of(track.id) == []
    end
  end

  defp russian_stereo do
    %{
      selector_type: :track,
      stream_kind: :audio,
      stream_language: "rus",
      stream_disposition: ["default"],
      stream_channels: 2,
      stream_ordinal: 1
    }
  end

  defp manifestation!(name) do
    {:ok, %{manifestation: manifestation}} = Catalog.create_work(name)
    manifestation
  end
end
