defmodule PluteusWeb.NativeApiTest do
  @moduledoc """
  The native API: spec-07 §4 and criteria 6 to 10.
  """

  use PluteusWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Catalog
  alias Pluteus.Lifecycle
  alias Pluteus.Principals
  alias Pluteus.Repo
  alias Pluteus.StorageFixtures

  @subject "ada@example.test"

  setup %{conn: conn} do
    %{conn: through_proxy(conn, @subject)}
  end

  describe "6. A representation names related res by identifier and embeds none" do
    test "a work names its expressions, and each is only an identifier", %{conn: conn} do
      {:ok, %{work: work, expression: expression}} = Catalog.create_work("Kind of Blue")

      body = conn |> get("/works/#{work.id}") |> json_response(200)

      assert %{"id" => id, "kind" => "work", "state" => "live", "name" => "Kind of Blue"} = body
      assert id == work.id
      assert body["related"]["expressions"] == [expression.id]
      assert Enum.all?(body["related"], fn {_relation, value} -> not is_map(value) end)
    end

    test "a member's name outranks placement's, and language picks among them", %{conn: conn} do
      {:ok, %{work: work}} =
        Catalog.create_work(%{nomen_string: "Symphonie", provenance: :automatic})

      conn
      |> post("/nomens", %{"res_id" => work.id, "nomen_string" => "Symphony", "language" => "en"})
      |> json_response(201)

      assert %{"name" => "Symphony"} = conn |> get("/works/#{work.id}") |> json_response(200)

      conn
      |> post("/nomens", %{"res_id" => work.id, "nomen_string" => "Sinfonie", "language" => "de"})
      |> json_response(201)

      names =
        for language <- ~w(en de) do
          conn
          |> get("/works/#{work.id}", %{"language" => language})
          |> json_response(200)
          |> Map.fetch!("name")
        end

      assert names == ["Symphony", "Sinfonie"]
    end
  end

  describe "7. Keyset paging neither skips nor repeats" do
    test "a work created and one recycled between pages disturb nothing else", %{conn: conn} do
      works =
        for n <- 1..5 do
          {:ok, %{work: work}} = Catalog.create_work("Work #{n}")
          work.id
        end

      first = conn |> get("/works", %{"limit" => "2"}) |> json_response(200)
      first_ids = Enum.map(first["items"], & &1["id"])

      {:ok, %{work: late}} = Catalog.create_work("Late work")
      principal = Principals.principal_for(issuer(), @subject)
      {:ok, _} = Lifecycle.recycle(hd(first_ids), principal.id)
      unseen = List.last(works)
      {:ok, _} = Lifecycle.recycle(unseen, principal.id)

      rest = page_through(conn, first["after"])

      seen = first_ids ++ rest
      assert Enum.uniq(seen) == seen
      assert Enum.all?(works -- [unseen], &(&1 in seen))
      refute unseen in seen
      assert late.id in seen
    end

    test "a limit outside the bounds is refused", %{conn: conn} do
      assert conn |> get("/works", %{"limit" => "0"}) |> json_response(400)
      assert conn |> get("/works", %{"limit" => "501"}) |> json_response(400)
      assert conn |> get("/works", %{"after" => "not-an-id"}) |> json_response(400)
    end
  end

  describe "8. Asset content honours byte ranges and is served as stored" do
    setup do
      bytes = StorageFixtures.png("served as stored")
      %{asset: asset_of(bytes), bytes: bytes}
    end

    test "the whole, with the format's media type", %{conn: conn, asset: asset, bytes: bytes} do
      response = get(conn, "/assets/#{asset.id}/content")

      assert response.status == 200
      assert response.resp_body == bytes
      assert get_resp_header(response, "content-type") == ["image/png"]
      assert get_resp_header(response, "accept-ranges") == ["bytes"]
    end

    test "a range, a suffix, and one beyond the end", %{conn: conn, asset: asset, bytes: bytes} do
      size = byte_size(bytes)

      ranged = conn |> put_req_header("range", "bytes=2-9") |> get("/assets/#{asset.id}/content")
      assert ranged.status == 206
      assert ranged.resp_body == binary_part(bytes, 2, 8)
      assert get_resp_header(ranged, "content-range") == ["bytes 2-9/#{size}"]

      suffix = conn |> put_req_header("range", "bytes=-4") |> get("/assets/#{asset.id}/content")
      assert suffix.status == 206
      assert suffix.resp_body == binary_part(bytes, size - 4, 4)

      beyond =
        conn
        |> put_req_header("range", "bytes=#{size + 10}-")
        |> get("/assets/#{asset.id}/content")

      assert beyond.status == 416
      assert get_resp_header(beyond, "content-range") == ["bytes */#{size}"]
    end
  end

  describe "9. Recycled, purged and absent are told apart" do
    test "each answers its own status and type", %{conn: conn} do
      principal = Principals.principal_for(issuer(), @subject) || admitted(conn)
      {:ok, %{work: recycled}} = Catalog.create_work("Recycled")
      {:ok, %{work: purged}} = Catalog.create_work("Purged")
      {:ok, _} = Lifecycle.recycle(recycled.id, principal.id)
      {:ok, recycling} = Lifecycle.recycle(purged.id, principal.id)
      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())

      gone = conn |> get("/works/#{recycled.id}") |> json_response(410)
      assert gone["type"] =~ "/problems/recycled"
      assert gone["restorable_until"]

      assert conn |> get("/works/#{purged.id}") |> json_response(410) |> Map.fetch!("type") =~
               "/problems/purged"

      assert conn
             |> get("/works/#{UUIDv7.generate()}")
             |> json_response(404)
             |> Map.fetch!("type") =~ "/problems/not-found"
    end

    test "deleting recycles, and restoring brings it back", %{conn: conn} do
      {:ok, %{work: work}} = Catalog.create_work("Kind of Blue")

      recycled = conn |> delete("/works/#{work.id}") |> json_response(200)
      assert work.id in recycled["contents"]
      assert conn |> get("/works/#{work.id}") |> json_response(410)

      conn |> post("/recyclings/#{recycled["recycling"]}/restoration") |> json_response(200)
      assert conn |> get("/works/#{work.id}") |> json_response(200)
    end
  end

  describe "10. Another principal's consumption datum answers 404" do
    test "another's device cannot be revoked, and is not confirmed to exist", %{conn: conn} do
      {:ok, other} = Principals.create_principal(%{role: "member"})
      {:ok, %{device: device}} = Principals.mint_key(other.id, "Grace's phone")

      assert conn |> delete("/devices/#{device.id}") |> json_response(404)
    end
  end

  describe "writes are attributed to the requesting principal" do
    test "a name written through the API is recorded as the principal's write", %{conn: conn} do
      {:ok, %{work: work}} = Catalog.create_work("Untitled")

      nomen =
        conn
        |> post("/nomens", %{"res_id" => work.id, "nomen_string" => "Titled"})
        |> json_response(201)

      principal = Principals.principal_for(issuer(), @subject)

      writers =
        Repo.all(
          from w in "catalog_writes",
            where: w.table_name == "nomens" and fragment("?->>'id'", w.row_key) == ^nomen["id"],
            select: type(w.principal_id, UUIDv7)
        )

      assert writers == [principal.id]
    end

    test "a correction of a category replaces the member's earlier one", %{conn: conn} do
      {:ok, %{work: work}} = Catalog.create_work("A song")

      conn
      |> post("/works/#{work.id}/categories", %{"scheme" => "genre", "value" => "Jazz"})
      |> json_response(201)

      conn
      |> post("/works/#{work.id}/categories", %{"scheme" => "genre", "value" => "Modal jazz"})
      |> json_response(201)

      assert Catalog.category_of(work.id, "genre") == "Modal jazz"
    end

    test "a write a constraint refuses is 422 naming the constraint", %{conn: conn} do
      body =
        conn
        |> post("/nomens", %{"res_id" => UUIDv7.generate(), "nomen_string" => "Of nothing"})
        |> json_response(422)

      assert body["type"] =~ "/problems/constraint"
      assert %{"res_id" => [%{"constraint" => "nomens_res_id_fkey"}]} = body["detail"]
    end
  end

  defp page_through(_conn, nil), do: []

  defp page_through(conn, after_id) do
    page = conn |> get("/works", %{"limit" => "2", "after" => after_id}) |> json_response(200)
    Enum.map(page["items"], & &1["id"]) ++ page_through(conn, page["after"])
  end

  defp admitted(conn) do
    conn |> get("/works") |> json_response(200)
    Principals.principal_for(issuer(), @subject)
  end

  defp asset_of(bytes) do
    {:ok, %{manifestation: manifestation}} = Catalog.create_work("Letter")
    {:ok, %{digital_item: item}} = Catalog.create_digital_item(manifestation.id, "Letter")

    {:ok, %{asset: asset}} =
      Catalog.create_asset(
        item.id,
        %{
          location: StorageFixtures.stored!("letter.png", bytes),
          essence: :lossless,
          verification_interval_seconds: 86_400,
          roles: [%{role_class: :acquired, role: "original-scan"}]
        },
        "letter.png"
      )

    asset
  end
end
