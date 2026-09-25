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

  import Pluteus.IngestFixtures

  alias Pluteus.Catalog
  alias Pluteus.Catalog.DigitalItem
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

  defp a_photograph(inbox) do
    [photo] = ingest!(inbox, %{"holiday/IMG_0001.png" => media!(:png)})
    {photo, manifestation_of(photo)}
  end

  defp held!(subject_id, profile, source) do
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
        width: 320,
        height: 240,
        descriptor: %{"width" => 320},
        source_asset_id: source.id,
        source_digest: source.digest,
        generated_at: DateTime.utc_now(),
        last_served_at: DateTime.utc_now()
      })

    held
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
