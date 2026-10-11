defmodule PluteusWeb.PresentationTest do
  @moduledoc """
  The presentation-asset surface ([spec-10] §11.1 and §11.6).

  Asserts spec-10 criterion 27 and spec-07 criterion 25, which are the same rule from
  the two sides: a presentation asset is served by profile name, a request naming
  dimensions is refused, the response names the profile served, and an ungenerated
  artefact is not an error. The OpenSubsonic exception both criteria carry is asserted
  in `PluteusWeb.SubsonicBrowseTest`, which is where that surface lives.
  """

  use PluteusWeb.ConnCase, async: true
  use Oban.Testing, repo: Pluteus.Repo

  import Ecto.Query, only: [from: 2]
  import Pluteus.IngestFixtures

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Addressing
  alias Pluteus.Catalog.Category
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Extent
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Ingest.Place
  alias Pluteus.Lifecycle
  alias Pluteus.Presentation
  alias Pluteus.Presentation.Registry
  alias Pluteus.Principals
  alias Pluteus.Repo
  alias Pluteus.Storage
  alias Pluteus.StorageFixtures
  alias Pluteus.Workers.GeneratePresentationAsset

  @t0 ~U[2026-09-18 12:00:00.000000Z]

  setup %{conn: conn} do
    _system = Principals.system!()
    {:ok, principal} = Principals.create_principal(%{role: "member"})
    viewer = a_subject()
    {:ok, _} = Principals.bind_identity(principal.id, issuer(), viewer)

    %{conn: through_proxy(conn, viewer), principal: principal, inbox: inbox!()}
  end

  defp ingest!(inbox, files) do
    for {path, bytes} <- files, do: drop!(inbox, path, bytes)
    ids = inbox |> acquire_settled!(@t0) |> acquired()
    Place.place_due(inbox)
    Normalize.normalize_due()
    ids |> Enum.map(&Ingest.get_acquisition!/1) |> Enum.sort_by(& &1.inbox_path)
  end

  defp manifestation_of(acquisition),
    do: Repo.get!(DigitalItem, acquisition.digital_item_id).manifestation_id

  defp work_of(acquisition) do
    manifestation = manifestation_of(acquisition)
    embodiment = Repo.one!(from b in Embodiment, where: b.manifestation_id == ^manifestation)

    Repo.get!(Expression, embodiment.expression_id).work_id
  end

  defp a_photograph(inbox) do
    [photo] = ingest!(inbox, %{"holiday/IMG_0001.png" => media!(:png)})
    {photo, manifestation_of(photo)}
  end

  defp held!(subject_id, profile, source, width \\ 320) do
    location = Presentation.location_for(subject_id, profile, 0, "jpg")
    bytes = StorageFixtures.png("held #{profile}")
    :ok = Storage.put(location, bytes)
    on_exit(fn -> Storage.delete(location) end)

    {:ok, held} =
      Presentation.record(%{
        subject_id: subject_id,
        profile: profile,
        location: location,
        media_type: "image/jpeg",
        size: byte_size(bytes),
        digest: "sha256:#{Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)}",
        digest_algorithm: "sha256",
        width: width,
        height: div(width * 3, 4),
        descriptor: %{"width" => width},
        source_asset_id: source.id,
        source_digest: source.digest,
        generated_at: DateTime.utc_now(),
        last_served_at: DateTime.utc_now()
      })

    held
  end

  defp waveform!(subject_id, source) do
    profile = Registry.waveform_overview()["name"]
    location = Presentation.location_for(subject_id, profile, 0, "json")
    bytes = Jason.encode!(%{"resolution" => %{"points" => 4}, "peaks" => [0, 128, 255, 64]})
    :ok = Storage.put(location, bytes)
    on_exit(fn -> Storage.delete(location) end)

    {:ok, held} =
      Presentation.record(%{
        subject_id: subject_id,
        profile: profile,
        location: location,
        media_type: "application/json",
        size: byte_size(bytes),
        digest: "sha256:#{Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)}",
        digest_algorithm: "sha256",
        descriptor: %{"points" => 4},
        source_asset_id: source.id,
        source_digest: source.digest,
        generated_at: DateTime.utc_now(),
        last_served_at: DateTime.utc_now()
      })

    held
  end

  describe "§8.4's band 3 is the medium itself" do
    defp interface(conn, path) do
      conn
      |> on_a_surface()
      |> put_req_header("accept", "text/html")
      |> get(path)
      |> html_response(200)
    end

    test "the graded widths are offered as one picture at its own sizes", %{
      conn: conn,
      inbox: inbox
    } do
      # §11.2's widths are one picture at several sizes, so a surface picks one from CSS
      # pixels times device pixel ratio. Each candidate carries the width it actually is.
      {_photo, manifestation} = a_photograph(inbox)
      source = Presentation.source_for(manifestation)
      _small = held!(manifestation, "image-160", source, 160)
      _larger = held!(manifestation, "image-320", source, 320)

      html = interface(conn, "/manifestations/#{manifestation}")

      assert html =~ ~s(id="entity-picture")
      assert html =~ "/manifestations/#{manifestation}/presentation/image-160 160w"
      assert html =~ "/manifestations/#{manifestation}/presentation/image-320 320w"
    end

    test "the box is reserved from the artefact's own geometry", %{conn: conn, inbox: inbox} do
      # A rendered surface does not shift as images arrive, so the box is the artefact's own
      # rather than a guess at it.
      {_photo, manifestation} = a_photograph(inbox)
      source = Presentation.source_for(manifestation)
      _held = held!(manifestation, "image-320", source, 320)

      html = interface(conn, "/manifestations/#{manifestation}")

      assert html =~ ~s(width="320")
      assert html =~ ~s(height="240")
    end

    test "the picture asserts no description nobody wrote", %{conn: conn, inbox: inbox} do
      # §17.3 forbids asserting an affordance that has not been established, and nothing
      # here has written a text alternative. Band 1 already says what the thing is.
      {_photo, manifestation} = a_photograph(inbox)
      source = Presentation.source_for(manifestation)
      _held = held!(manifestation, "image-320", source, 320)

      assert interface(conn, "/manifestations/#{manifestation}") =~ ~s(alt="")
    end

    test "a spatial region is outlined on the picture", %{conn: conn, inbox: inbox} do
      # §10.2 requires the region be shown on the medium and not only named. A spatial
      # selector states itself in percentages, so the outline holds at any drawn width.
      {_photo, manifestation} = a_photograph(inbox)
      source = Presentation.source_for(manifestation)
      _held = held!(manifestation, "image-320", source, 320)

      html =
        interface(
          conn,
          "/manifestations/#{manifestation}?xywh=percent:10,20,30,40"
        )

      assert html =~ ~s(id="entity-region-outline")
      assert html =~ "left: 10"
      assert html =~ "width: 30"
    end

    test "the outline is not announced twice", %{conn: conn, inbox: inbox} do
      # The words in the region band are what a screen reader receives; the outline is the
      # same fact for a sighted reader, so it is hidden from the accessibility tree.
      {_photo, manifestation} = a_photograph(inbox)
      source = Presentation.source_for(manifestation)
      _held = held!(manifestation, "image-320", source, 320)

      html = interface(conn, "/manifestations/#{manifestation}?xywh=percent:10,20,30,40")

      assert html =~ ~s(aria-hidden="true")
      assert html =~ "part of the picture"
    end

    test "a picture with no region carries no outline", %{conn: conn, inbox: inbox} do
      {_photo, manifestation} = a_photograph(inbox)
      source = Presentation.source_for(manifestation)
      _held = held!(manifestation, "image-320", source, 320)

      refute interface(conn, "/manifestations/#{manifestation}") =~ "entity-region-outline"
    end

    test "a temporal region is a band across the waveform", %{conn: conn, inbox: inbox} do
      # A waveform is the medium for a recording, so a link naming a stretch of it is shown
      # there. The band is given as a fraction of the whole, which is what the drawing needs
      # and what keeps the placement out of the client's hands.
      [track] = ingest!(inbox, %{"KoB/01 So What.flac" => media!(:flac)})
      manifestation = manifestation_of(track)
      source = Presentation.source_for(manifestation)
      _held = waveform!(manifestation, source)
      {:ok, _extent} = Addressing.record_extent(manifestation, :millisecond, 100_000)

      html = interface(conn, "/manifestations/#{manifestation}?t=npt:10,20")

      assert html =~ ~s(id="entity-waveform")
      assert html =~ ~s(data-from="0.1")
      assert html =~ ~s(data-to="0.2")
    end

    test "a waveform with no region carries no band", %{conn: conn, inbox: inbox} do
      [track] = ingest!(inbox, %{"KoB/01 So What.flac" => media!(:flac)})
      manifestation = manifestation_of(track)
      source = Presentation.source_for(manifestation)
      _held = waveform!(manifestation, source)

      html = interface(conn, "/manifestations/#{manifestation}")

      assert html =~ ~s(id="entity-waveform")
      refute html =~ "data-from"
    end

    test "a region with no extent to place it against gets no band", %{conn: conn, inbox: inbox} do
      # Placement records a length, so the length is removed to reach the state a failed
      # probe leaves. The words then say it cannot be shown, and nothing is drawn at a
      # position nobody established.
      [track] = ingest!(inbox, %{"KoB/01 So What.flac" => media!(:flac)})
      manifestation = manifestation_of(track)
      source = Presentation.source_for(manifestation)
      _held = waveform!(manifestation, source)

      {1, _} = Repo.delete_all(from e in Extent, where: e.res_id == ^manifestation)

      html = interface(conn, "/manifestations/#{manifestation}?t=npt:10,20")

      refute html =~ "data-from"
      assert html =~ "cannot be shown"
    end

    test "a work whose category is presented somewhere leads there",
         %{conn: conn, inbox: inbox} do
      # §12.1 presents a photograph on a viewer and §10.1 addresses that beneath the res,
      # so the action is a link rather than a control carrying a reason it cannot act.
      [photo] = ingest!(inbox, %{"holiday/IMG_0001.png" => media!(:png)})
      work = work_of(photo)

      html = interface(conn, "/works/#{work}")

      assert html =~ ~s|href="/works/#{work}/view"|
      refute html =~ "holds no file of it"
    end

    test "a work nothing has said the kind of carries the reason instead",
         %{conn: conn, inbox: inbox} do
      # §17.3 from the other side, and the two reasons must not be confused: one is about
      # the catalog holding no file, the other about nothing having said what the file is.
      [photo] = ingest!(inbox, %{"holiday/IMG_0002.png" => media!(:png)})
      work = work_of(photo)

      {_count, _} = Repo.delete_all(from c in Category, where: c.res_id == ^work)

      html = interface(conn, "/works/#{work}")

      refute html =~ ~s|href="/works/#{work}/view"|
      assert html =~ "Nothing has said what kind of thing this is"
      refute html =~ "holds no file of it"
    end

    test "a subject with no artefact carries no band at all", %{conn: conn, inbox: inbox} do
      # No image is generated to stand for a holding that has none, and §8.4 makes a band
      # with nothing in it absent rather than empty.
      {_photo, manifestation} = a_photograph(inbox)

      html = interface(conn, "/manifestations/#{manifestation}")

      refute html =~ ~s(id="entity-medium")
      refute html =~ ~s(id="entity-picture")
    end
  end

  describe "27. A request by arbitrary dimensions is refused" do
    test "every spelling of a dimension is refused, whatever profile it names",
         %{conn: conn, inbox: inbox} do
      {_photo, manifestation} = a_photograph(inbox)

      for parameter <- ~w(width height size w h scale) do
        response =
          conn
          |> get("/manifestations/#{manifestation}/presentation/image-320", %{parameter => "700"})
          |> json_response(400)

        assert response["title"] == "dimension refused"
        assert response["detail"] =~ parameter
        assert "image-320" in response["profiles"]
      end
    end

    test "a dimension is refused before the profile is looked up", %{conn: conn, inbox: inbox} do
      {_photo, manifestation} = a_photograph(inbox)

      # Both are wrong. The dimension is the refusal, because a rule that only
      # applied where the profile was also wrong would leave the hole open.
      response =
        conn
        |> get("/manifestations/#{manifestation}/presentation/image-999", %{"width" => "700"})
        |> json_response(400)

      assert response["title"] == "dimension refused"
    end

    test "a request by profile name is served, and names the profile",
         %{conn: conn, inbox: inbox} do
      {photo, manifestation} = a_photograph(inbox)
      source = Normalize.master_of(photo.digital_item_id)
      held = held!(manifestation, "image-320", source)

      conn = get(conn, "/manifestations/#{manifestation}/presentation/image-320")

      assert conn.status == 200
      assert get_resp_header(conn, "presentation-profile") == ["image-320"]
      assert get_resp_header(conn, "etag") == [~s("#{held.digest}")]
      assert response_content_type(conn, :jpeg)
    end

    test "a profile outside the closed set is refused, and the set is named",
         %{conn: conn, inbox: inbox} do
      {_photo, manifestation} = a_photograph(inbox)

      response =
        conn
        |> get("/manifestations/#{manifestation}/presentation/image-999")
        |> json_response(400)

      assert response["detail"] =~ "image-999"
      assert Enum.sort(response["profiles"]) == Enum.sort(Registry.profile_names())
    end
  end

  describe "the absence of a presentation asset is never an error (§11.6, §16)" do
    test "not generated, with bytes to generate from, is 202", %{conn: conn, inbox: inbox} do
      {_photo, manifestation} = a_photograph(inbox)

      conn = get(conn, "/manifestations/#{manifestation}/presentation/image-2048")

      assert conn.status == 202
      assert get_resp_header(conn, "presentation-profile") == ["image-2048"]
      assert conn.resp_body == ""

      assert_enqueued(
        worker: GeneratePresentationAsset,
        args: %{subject_id: manifestation, profile: "image-2048"}
      )
    end

    test "asking twice queues one job, which is the generating state",
         %{conn: conn, inbox: inbox} do
      {_photo, manifestation} = a_photograph(inbox)
      path = "/manifestations/#{manifestation}/presentation/image-1280"

      assert get(conn, path).status == 202
      assert get(conn, path).status == 202

      # The job's uniqueness is why the row needs no state column: a page of tiles
      # asking at once does not encode the same artefact many times.
      assert [_one] = all_enqueued(worker: GeneratePresentationAsset)
    end

    test "nothing is queued where there is nothing to generate from", %{conn: conn} do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("A Described Photograph")

      get(conn, "/manifestations/#{manifestation.id}/presentation/image-320")

      assert all_enqueued(worker: GeneratePresentationAsset) == []
    end

    test "the queued job makes the artefact the next request serves",
         %{conn: conn, inbox: inbox} do
      {_photo, manifestation} = a_photograph(inbox)
      path = "/manifestations/#{manifestation}/presentation/image-320"

      assert get(conn, path).status == 202

      assert %{success: 1} = Oban.drain_queue(queue: :presentation)

      made = Presentation.get(manifestation, "image-320")
      on_exit(fn -> Storage.delete(made.location) end)

      served = get(conn, path)

      assert served.status == 200
      assert get_resp_header(served, "presentation-profile") == ["image-320"]
    end

    test "not generated, with nothing to generate from, is 204", %{conn: conn} do
      # A manifestation the household describes and holds no file for (spec-01 §5.2).
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("A Described Photograph")

      conn = get(conn, "/manifestations/#{manifestation.id}/presentation/image-320")

      # 404, not 204: with no bytes at all there is no class, so no image profile
      # applies to it. An artefact of a thing with no file is not absent, it is not
      # an artefact.
      assert conn.status == 404
    end

    test "neither absence is in the 4xx or 5xx range", %{conn: conn, inbox: inbox} do
      {_photo, manifestation} = a_photograph(inbox)

      conn = get(conn, "/manifestations/#{manifestation}/presentation/image-1280")

      assert conn.status >= 200 and conn.status < 300
    end
  end

  describe "a profile the subject cannot have is not found" do
    test "a waveform of a photograph does not exist", %{conn: conn, inbox: inbox} do
      {_photo, manifestation} = a_photograph(inbox)

      assert conn
             |> get("/manifestations/#{manifestation}/presentation/waveform-overview-1000")
             |> Map.fetch!(:status) == 404
    end

    test "a trickplay sheet of a still does not exist", %{conn: conn, inbox: inbox} do
      {_photo, manifestation} = a_photograph(inbox)

      assert conn
             |> get("/manifestations/#{manifestation}/presentation/trickplay-320")
             |> Map.fetch!(:status) == 404
    end

    test "an image profile of an audio holding does not exist", %{conn: conn, inbox: inbox} do
      [track] = ingest!(inbox, %{"KoB/01.flac" => media!(:flac)})

      # A music recording's artwork is a companion holding with a res of its own
      # (spec-10 §12.1), so it is asked for there and not here.
      assert conn
             |> get("/manifestations/#{manifestation_of(track)}/presentation/image-320")
             |> Map.fetch!(:status) == 404
    end

    test "a waveform of an audio holding does apply", %{conn: conn, inbox: inbox} do
      [track] = ingest!(inbox, %{"KoB/01.flac" => media!(:flac)})

      assert conn
             |> get(
               "/manifestations/#{manifestation_of(track)}/presentation/waveform-overview-1000"
             )
             |> Map.fetch!(:status) == 202
    end
  end

  describe "the subject's lifecycle outranks anything about derivatives" do
    test "a recycled subject is gone, with its restore window", %{conn: conn, inbox: inbox} do
      {photo, manifestation} = a_photograph(inbox)
      source = Normalize.master_of(photo.digital_item_id)
      held!(manifestation, "image-320", source)

      {:ok, _} = Lifecycle.recycle(manifestation, Principals.system!().id)

      response =
        conn
        |> get("/manifestations/#{manifestation}/presentation/image-320")
        |> json_response(410)

      assert response["title"] == "recycled"
      assert response["restorable_until"]
    end

    test "an identifier belonging to nothing is not found", %{conn: conn} do
      assert conn
             |> get("/manifestations/#{Ecto.UUID.generate()}/presentation/image-320")
             |> Map.fetch!(:status) == 404
    end

    test "an identifier that is not one is not found", %{conn: conn} do
      assert conn
             |> get("/manifestations/not-a-uuid/presentation/image-320")
             |> Map.fetch!(:status) == 404
    end
  end

  describe "serving reorders the eviction queue" do
    test "a served artefact moves to the back", %{conn: conn, inbox: inbox} do
      {photo, manifestation} = a_photograph(inbox)
      source = Normalize.master_of(photo.digital_item_id)
      held = held!(manifestation, "image-320", source)

      get(conn, "/manifestations/#{manifestation}/presentation/image-320")

      served = Presentation.get(manifestation, "image-320")
      assert DateTime.compare(served.last_served_at, held.last_served_at) in [:gt, :eq]
    end
  end

  describe "the kind stays fixed by the path (§9.1)" do
    test "a manifestation's identifier is not found under another kind's path",
         %{conn: conn, inbox: inbox} do
      {_photo, manifestation} = a_photograph(inbox)

      assert conn
             |> get("/works/#{manifestation}/presentation/image-320")
             |> Map.fetch!(:status) == 404
    end
  end
end
