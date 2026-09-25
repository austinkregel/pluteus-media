defmodule Pluteus.Presentation.GeometryTest do
  @moduledoc """
  [spec-10] §11.2's geometry-before-bytes rule, and criterion 28: a visual res's
  geometry is available in the batched call that resolves its name, and a rendered
  collection does not shift as images arrive.
  """

  use Pluteus.DataCase, async: true

  import Pluteus.IngestFixtures

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Profile
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Place
  alias Pluteus.Presentation.Geometry
  alias Pluteus.Presentation.Registry
  alias Pluteus.Principals
  alias Pluteus.Representation

  @t0 ~U[2026-09-18 12:00:00.000000Z]

  setup do
    _system = Principals.system!()
    %{inbox: inbox!()}
  end

  defp ingest!(inbox, files) do
    for {path, bytes} <- files, do: drop!(inbox, path, bytes)
    ids = inbox |> acquire_settled!(@t0) |> acquired()
    Place.place_due(inbox)
    ids |> Enum.map(&Ingest.get_acquisition!/1) |> Enum.sort_by(& &1.inbox_path)
  end

  defp manifestation_of(acquisition),
    do: Repo.get!(Pluteus.Catalog.DigitalItem, acquisition.digital_item_id).manifestation_id

  describe "28. A visual res's geometry is available in the batched call" do
    test "a still image answers the pixels the probe read", %{inbox: inbox} do
      [photo] = ingest!(inbox, %{"holiday/IMG_0001.png" => media!(:png)})
      manifestation = manifestation_of(photo)

      found = Geometry.for_res([manifestation])

      # `still/0` renders 64x48, so the ratio is four thirds.
      assert %{width: 64, height: 48, aspect_ratio: ratio} = found[manifestation]
      assert_in_delta ratio, 1.3333, 0.001
    end

    test "a moving image answers its frame, not its duration", %{inbox: inbox} do
      [film] = ingest!(inbox, %{"home/birthday.mkv" => media!(:ffv1)})

      assert %{width: 64, height: 48} =
               Geometry.for_res([manifestation_of(film)])
               |> Map.values()
               |> hd()
    end

    test "audio carrying no picture answers nothing", %{inbox: inbox} do
      [track] = ingest!(inbox, %{"KoB/01.flac" => media!(:flac)})

      assert Geometry.for_res([manifestation_of(track)]) == %{}
    end

    test "embedded cover art is not the holding's geometry", %{inbox: inbox} do
      # A FLAC carrying a JPEG of its sleeve has a video stream, and that stream is
      # an attached picture. Its dimensions are the artwork's.
      [track] = ingest!(inbox, %{"KoB/01.flac" => media!(:flac, art: true)})

      assert Geometry.for_res([manifestation_of(track)]) == %{}
    end

    test "a page of res costs one batched call, not one per tile", %{inbox: inbox} do
      placed =
        ingest!(inbox, %{
          "a/one.png" => media!(:png),
          "b/two.png" => media!(:jpeg),
          "c/three.mkv" => media!(:ffv1)
        })

      subjects = Enum.map(placed, &manifestation_of/1)

      found = Geometry.for_res(subjects)

      assert map_size(found) == 3
      assert Enum.all?(subjects, &Map.has_key?(found, &1))
    end

    test "no res is no query", do: assert(Geometry.for_res([]) == %{})

    test "the geometry reaches the representation that resolves the name",
         %{inbox: inbox} do
      [photo] = ingest!(inbox, %{"holiday/IMG_0001.png" => media!(:png)})
      manifestation = Repo.get!(Catalog.Res, manifestation_of(photo))

      [representation] = Representation.of_many([manifestation], %Profile{})

      assert representation["geometry"] == %{
               "state" => "held",
               "value" => %{"width" => 64, "height" => 48, "aspect_ratio" => 1.3333}
             }

      # The same call resolved the name, which is what criterion 28 asks.
      assert representation["name"]["state"] == "held"
    end

    test "a res nobody probed reports not yet examined rather than a zero box" do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("An Unprobed Scan")
      res = Repo.get!(Catalog.Res, manifestation.id)

      [representation] = Representation.of_many([res], %Profile{})

      assert representation["geometry"] == %{"state" => "not_yet_examined"}
      refute Map.has_key?(representation["geometry"], "value")
    end
  end

  describe "a collection reserves a box before any bytes arrive" do
    test "a measured res reserves its own ratio" do
      measured = %{width: 1600, height: 1200, aspect_ratio: 1.3333}

      assert Geometry.reserve(measured, "photograph") == 1.3333
    end

    test "an unprobed res reserves the ratio §20 names for its category" do
      assert Geometry.reserve(nil, "scan") == Registry.assumed_aspect_ratio("scan")
      assert Geometry.reserve(nil, "comic_issue") == 0.6471
      assert Geometry.reserve(nil, "film") == 0.6667
    end

    test "every category §20 names a ratio for reserves something" do
      for category <- Registry.categories_with_ratio() do
        assert Geometry.reserve(nil, category) > 0,
               "#{category} reserves nothing, so a tile of it collapses"
      end
    end

    test "a companion kind reserves nothing, because nothing draws it" do
      assert Geometry.reserve(nil, "lyrics") == nil
      assert Geometry.reserve(nil, "subtitles") == nil
    end

    test "a category outside the registry raises rather than guessing" do
      assert_raise KeyError, fn -> Geometry.reserve(nil, "hologram") end
    end
  end

  describe "28. …and a rendered collection does not shift as images arrive" do
    test "the representation carries the ratio to reserve", %{inbox: inbox} do
      [photo] = ingest!(inbox, %{"holiday/IMG_0001.png" => media!(:png)})
      res = Repo.get!(Catalog.Res, manifestation_of(photo))

      [representation] = Representation.of_many([res], %Profile{})

      # Measured, so the ratio is the image's own.
      assert_in_delta representation["reserve_aspect_ratio"], 1.3333, 0.001
    end

    test "an unprobed res reserves its category's ratio, so the tile has a size" do
      {:ok, catalogued} = Catalog.create_work("An Unprobed Scan")

      {:ok, _} =
        Catalog.categorize(catalogued.work.id, Place.category_scheme(), "scan", :automatic)

      res = Repo.get!(Catalog.Res, catalogued.manifestation.id)

      [representation] = Representation.of_many([res], %Profile{})

      # Nothing has been probed, so the geometry is absent — and the ratio is still
      # answerable, which is what keeps the tile from collapsing to nothing.
      assert representation["geometry"] == %{"state" => "not_yet_examined"}
      assert representation["reserve_aspect_ratio"] == Registry.assumed_aspect_ratio("scan")
    end

    test "the category is read from the work, not from the manifestation" do
      {:ok, catalogued} = Catalog.create_work("A Film")

      {:ok, _} =
        Catalog.categorize(catalogued.work.id, Place.category_scheme(), "film", :automatic)

      # spec-04 §6.3 records the category on the work, so a manifestation carries none
      # of its own and the ratio has to be reached through it.
      assert Catalog.categories_of(catalogued.manifestation.id) == []

      res = Repo.get!(Catalog.Res, catalogued.manifestation.id)
      [representation] = Representation.of_many([res], %Profile{})

      assert representation["reserve_aspect_ratio"] == 0.6667
    end

    test "a res of no category and no geometry reserves nothing rather than zero" do
      {:ok, catalogued} = Catalog.create_work("An Uncategorized Thing")
      res = Repo.get!(Catalog.Res, catalogued.manifestation.id)

      [representation] = Representation.of_many([res], %Profile{})

      refute Map.has_key?(representation, "reserve_aspect_ratio")
    end
  end
end
