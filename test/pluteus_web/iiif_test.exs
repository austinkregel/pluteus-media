defmodule PluteusWeb.IiifTest do
  @moduledoc """
  [spec-10] §11.2's tiled pyramid, under the [IIIF-IMAGE] grammar: the information
  document, the tiles it offers, and the percentage region form the section requires be
  accepted and be translatable both ways.
  """

  use PluteusWeb.ConnCase, async: true
  use Oban.Testing, repo: Pluteus.Repo

  # Every test here encodes a sixteen-megapixel image and tiles it, which is minutes of
  # work rather than seconds when the whole suite is competing for the same cores. The
  # cost is stated rather than left to look like flakiness.
  @moduletag timeout: 300_000

  import Pluteus.IngestFixtures

  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Ingest.Place
  alias Pluteus.Presentation.Generate
  alias Pluteus.Presentation.Registry
  alias Pluteus.Presentation.Tiles
  alias Pluteus.Principals
  alias Pluteus.Repo
  alias Pluteus.Storage

  @t0 ~U[2026-09-18 12:00:00.000000Z]
  @viewer "ada@household.test"

  setup %{conn: conn} do
    _system = Principals.system!()
    {:ok, principal} = Principals.create_principal(%{role: "member"})
    {:ok, _} = Principals.bind_identity(principal.id, issuer(), @viewer)

    %{conn: through_proxy(conn, @viewer), inbox: inbox!()}
  end

  # Under a prefix of its own, because two async tests dropping one relative path
  # contend on the sighting and acquisition rows for as long as the slower one runs, and
  # the tests here are the slow ones.
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

  # Past §20's sixteen-megapixel threshold, so the pyramid is what §11.2 asks for.
  defp a_large_scan(inbox) do
    [scan] = ingest!(inbox, %{"letters/scan.png" => media!(:large_still)})
    manifestation_of(scan)
  end

  defp tiled!(subject) do
    {:ok, made} = Generate.run(subject, Registry.tiling()["name"])
    on_exit(fn -> Storage.delete(made.location) end)
    made
  end

  describe "a pyramid is built past the threshold and refused below it" do
    test "a large scan is tiled", %{inbox: inbox} do
      subject = a_large_scan(inbox)
      made = tiled!(subject)

      assert made.profile == "image-tiled"
      assert made.media_type == "application/zip"
      assert made.descriptor["tile_size"] == Registry.tiling()["tile_size"]
      assert made.descriptor["compliance_level"] == 0
      assert Storage.exists?(made.location)
    end

    test "a small image is not, because a profile set is simpler there", %{inbox: inbox} do
      [small] = ingest!(inbox, %{"holiday/IMG_0001.png" => media!(:png)})

      assert Generate.run(manifestation_of(small), "image-tiled") ==
               {:refused, :below_the_tiling_threshold}
    end

    test "the threshold is the registry's, not a number in the code" do
      threshold = Registry.tiling()["threshold_pixels"]

      refute Tiles.tiled?(4000, 4000)
      assert Tiles.tiled?(6000, 4000)
      assert threshold == 16_000_000
    end
  end

  describe "the information document is the contract" do
    test "it names this deployment's identifier, not the generator's placeholder",
         %{conn: conn, inbox: inbox} do
      subject = a_large_scan(inbox)
      tiled!(subject)

      document = conn |> get("/manifestations/#{subject}/iiif/info.json") |> json_response(200)

      # A document naming somebody else's host is worse than none: a client follows the
      # identifier it is given.
      assert document["id"] =~ "/manifestations/#{subject}/iiif"
      refute document["id"] =~ "example.com"
    end

    test "it states the tile size, the scale factors and the compliance level",
         %{conn: conn, inbox: inbox} do
      subject = a_large_scan(inbox)
      tiled!(subject)

      document = conn |> get("/manifestations/#{subject}/iiif/info.json") |> json_response(200)

      assert document["type"] == "ImageService3"
      assert document["profile"] == "level0"
      assert document["width"] > 0 and document["height"] > 0
      assert [%{"width" => 512, "scaleFactors" => [_ | _]}] = document["tiles"]
    end

    test "it declares the percentage region as an extra feature, not as a level",
         %{conn: conn, inbox: inbox} do
      subject = a_large_scan(inbox)
      tiled!(subject)

      document = conn |> get("/manifestations/#{subject}/iiif/info.json") |> json_response(200)

      # Claiming level 1 would promise the rest of level 1, which is not offered.
      assert document["profile"] == "level0"
      assert "regionByPct" in document["extraFeatures"]
    end
  end

  describe "the tiles the document offers are served" do
    test "a tile named by the pyramid is answered", %{conn: conn, inbox: inbox} do
      subject = a_large_scan(inbox)
      made = tiled!(subject)

      {:ok, document} = Tiles.information(made.location, "x")
      [%{"width" => size}] = document["tiles"]

      response =
        get(
          conn,
          "/manifestations/#{subject}/iiif/0,0,#{size},#{size}/#{size},#{size}/0/default.jpg"
        )

      assert response.status == 200
      assert get_resp_header(response, "presentation-profile") == ["image-tiled"]
      assert <<0xFF, 0xD8, _rest::binary>> = response.resp_body
    end

    test "a tile the pyramid does not hold is not found", %{conn: conn, inbox: inbox} do
      subject = a_large_scan(inbox)
      tiled!(subject)

      # Level 0 offers exactly what it generated. This is outside the offer rather than
      # a missing artefact.
      assert conn
             |> get("/manifestations/#{subject}/iiif/7,7,13,13/13,13/0/default.jpg")
             |> Map.fetch!(:status) == 404
    end

    test "a rotation or quality the pyramid does not offer is refused",
         %{conn: conn, inbox: inbox} do
      subject = a_large_scan(inbox)
      tiled!(subject)

      turned =
        conn
        |> get("/manifestations/#{subject}/iiif/0,0,512,512/512,512/90/default.jpg")
        |> json_response(400)

      assert turned["title"] == "tile refused"

      grey =
        conn
        |> get("/manifestations/#{subject}/iiif/0,0,512,512/512,512/0/gray.jpg")
        |> json_response(400)

      assert grey["title"] == "tile refused"
    end
  end

  describe "an absent pyramid is not an error" do
    test "with bytes to build from, the document is 202 and the work is queued",
         %{conn: conn, inbox: inbox} do
      subject = a_large_scan(inbox)

      response = get(conn, "/manifestations/#{subject}/iiif/info.json")

      assert response.status == 202

      assert_enqueued(
        worker: Pluteus.Workers.GeneratePresentationAsset,
        args: %{subject_id: subject, profile: "image-tiled"}
      )
    end

    test "a recycled subject is gone rather than absent", %{conn: conn, inbox: inbox} do
      subject = a_large_scan(inbox)
      tiled!(subject)

      {:ok, _} = Pluteus.Lifecycle.recycle(subject, Principals.system!().id)

      assert conn
             |> get("/manifestations/#{subject}/iiif/info.json")
             |> json_response(410)
             |> Map.fetch!("title") == "recycled"
    end

    test "an identifier belonging to another kind is not found", %{conn: conn, inbox: inbox} do
      subject = a_large_scan(inbox)

      assert conn
             |> get("/works/#{subject}/iiif/info.json")
             |> Map.fetch!(:status) == 404
    end
  end

  describe "a percentage region is translated, never stored" do
    test "the deep link's spelling becomes the grammar's" do
      assert Tiles.pct("percent:25,25,50,50") == "pct:25.0,25.0,50.0,50.0"
    end

    test "and the grammar's becomes the deep link's" do
      assert Tiles.xywh("pct:25,25,50,50") == "percent:25.0,25.0,50.0,50.0"
    end

    test "the translation round-trips" do
      assert "percent:10.5,20.25,30.0,40.0"
             |> Tiles.pct()
             |> Tiles.xywh() == "percent:10.5,20.25,30.0,40.0"
    end

    test "anything that is not a percentage region is refused" do
      assert Tiles.pct("0,0,512,512") == :error
      assert Tiles.pct("percent:25,25,50") == :error
      assert Tiles.pct("percent:a,b,c,d") == :error
      assert Tiles.xywh("full") == :error
    end

    test "a pixel region is never written anywhere", %{inbox: inbox} do
      subject = a_large_scan(inbox)
      made = tiled!(subject)

      # spec-01 §8.4 forbids a pixel region as an addressing basis. The pyramid's own
      # entries are pixel regions inside an archive, which is not an address; nothing
      # about them reaches a selector or the descriptor.
      refute Map.has_key?(made.descriptor, "region")

      assert Address.basis(:spatial) == [
               :x_percent,
               :y_percent,
               :width_percent,
               :height_percent
             ]
    end
  end
end
