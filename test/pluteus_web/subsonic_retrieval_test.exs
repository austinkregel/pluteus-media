defmodule PluteusWeb.SubsonicRetrievalTest do
  @moduledoc """
  `stream` and `download`: spec-07 §6.7 and criterion 20.
  """

  use PluteusWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]
  import Pluteus.IngestFixtures

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.AssetRole
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Place
  alias Pluteus.MusicFixtures
  alias Pluteus.Repo
  alias Pluteus.Storage

  setup %{conn: conn} do
    library = MusicFixtures.library!()

    %{"key" => key} =
      conn
      |> through_proxy("ada@example.test")
      |> post("/devices", %{"label" => "phone"})
      |> json_response(201)

    %{conn: via_proxy(conn), key: key, library: library}
  end

  describe "20. stream serves the master, download the original, as stored" do
    test "a WAV streams as its FLAC master and downloads as the WAV it arrived as", context do
      song = context.library.songs["untitled.wav"]
      {master, original} = assets_of(song)

      streamed = request(context, "stream", %{"id" => song})
      assert streamed.status == 200
      assert streamed.resp_body == Storage.read(master.location)
      assert get_resp_header(streamed, "content-type") == ["audio/flac"]

      downloaded = request(context, "download", %{"id" => song})
      assert downloaded.status == 200
      assert downloaded.resp_body == Storage.read(original.location)
      assert get_resp_header(downloaded, "content-type") == ["audio/wav"]
      refute downloaded.resp_body == streamed.resp_body
    end

    test "a format asked for changes nothing until spec-08", context do
      song = context.library.songs["untitled.wav"]
      {master, _original} = assets_of(song)

      streamed =
        request(context, "stream", %{"id" => song, "format" => "mp3", "maxBitRate" => "128"})

      assert streamed.resp_body == Storage.read(master.location)
      assert get_resp_header(streamed, "content-type") == ["audio/flac"]
    end

    test "a byte range is honoured", context do
      song = context.library.songs["01 So What.flac"]
      {master, _original} = assets_of(song)
      bytes = Storage.read(master.location)

      ranged =
        context.conn
        |> put_req_header("range", "bytes=4-19")
        |> get("/rest/stream", %{"id" => song, "apiKey" => context.key})

      assert ranged.status == 206
      assert ranged.resp_body == binary_part(bytes, 4, 16)
    end

    test "a track cut from a release in one file answers error 0 and says why", context do
      inbox = inbox!()

      for {path, bytes} <- %{
            "Cue/album.flac" => media!(:flac, duration: 6),
            "Cue/album.cue" => """
            TITLE "Cut"
            FILE "album.flac" WAVE
              TRACK 01 AUDIO
                TITLE "First"
                INDEX 01 00:00:00
              TRACK 02 AUDIO
                TITLE "Second"
                INDEX 01 00:03:00
            """
          },
          do: drop!(inbox, path, bytes)

      inbox |> acquire_settled!(~U[2026-09-18 12:00:00.000000Z]) |> acquired()
      Place.place_due(inbox)

      [album] =
        for acquisition <- Ingest.acquisitions_from("Cue/album.flac"),
            do: Repo.get!(DigitalItem, acquisition.digital_item_id).manifestation_id

      [%{part_id: medium}] = Catalog.parts_of(album)
      [%{part_id: first}, _second] = Catalog.parts_of(medium)

      song = call(context, "getSong", %{"id" => first})["song"]
      assert song["duration"] == 3

      for endpoint <- ["stream", "download"] do
        body = request(context, endpoint, %{"id" => first, "f" => "json"}) |> json_response(200)
        assert %{"code" => 0, "message" => message} = body["subsonic-response"]["error"]
        assert message =~ "transcode"
      end
    end

    test "an unknown song is error 70, and a missing one 10", context do
      assert error(context, "stream", %{"id" => UUIDv7.generate()}) == 70
      assert error(context, "download", %{"id" => "nope"}) == 70
      assert error(context, "stream", %{}) == 10
    end
  end

  # The master and the acquired original of a song's digital item.
  defp assets_of(song) do
    [item] = Repo.all(from d in DigitalItem, where: d.manifestation_id == ^song, select: d.id)

    roles =
      Map.new(
        Repo.all(
          from r in AssetRole,
            join: a in Asset,
            on: a.id == r.asset_id,
            where: a.digital_item_id == ^item,
            select: {r.role_class, a}
        )
      )

    {roles[:normalized], roles[:acquired]}
  end

  defp request(context, endpoint, params),
    do: get(context.conn, "/rest/#{endpoint}", Map.put(params, "apiKey", context.key))

  defp call(context, endpoint, params) do
    body =
      context
      |> request(endpoint, Map.put(params, "f", "json"))
      |> json_response(200)
      |> Map.fetch!("subsonic-response")

    assert body["status"] == "ok", inspect(body["error"])
    body
  end

  defp error(context, endpoint, params) do
    body =
      context
      |> request(endpoint, Map.put(params, "f", "json"))
      |> json_response(200)
      |> Map.fetch!("subsonic-response")

    body["error"]["code"]
  end
end
