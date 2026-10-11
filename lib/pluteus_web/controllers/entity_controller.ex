defmodule PluteusWeb.EntityController do
  @moduledoc """
  Serves a res kind's collection and each res at the URI §9.1 gives it,
  answering for its lifecycle state as §14.2 requires (spec-07 §4).

  A recycled entity is `410 Gone` with `Cache-Control: no-store`. 410 is
  cacheable by default, and a cached tombstone would outlive a restore; the
  problem body says when the window closes so a client can offer to restore
  it. A purged entity is `410 Gone` too, with default cacheability left in
  place, because its permanence is then accurate.

  A collection lists live res only, paged by keyset on the identifier: the
  identifier is time-ordered, so a res created between two pages lands on a
  later page, and one recycled between them leaves the others where they were.
  """

  use PluteusWeb, :controller

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Catalog.DeepLink
  alias Pluteus.Catalog.Res
  alias Pluteus.Lifecycle
  alias Pluteus.Lifecycle.RecycledRes
  alias Pluteus.Lifecycle.Tombstone
  alias Pluteus.Repo
  alias Pluteus.Representation
  alias PluteusWeb.Native
  alias PluteusWeb.Problem

  def index(conn, _params) do
    kind = conn.assigns.kind

    case Native.page(conn) do
      {:ok, limit, after_id} ->
        res = live_page(kind, limit + 1, after_id)
        {shown, more} = Enum.split(res, limit)
        profile = Native.profile(conn)

        json(conn, %{
          "items" => Representation.of_many(shown, profile),
          "after" => if(more == [], do: nil, else: List.last(shown).id)
        })

      {:error, detail} ->
        Native.invalid(conn, detail)
    end
  end

  defp live_page(kind, limit, after_id) do
    query =
      from r in Res,
        where: r.kind == ^kind,
        where: r.id not in subquery(from b in RecycledRes, select: b.res_id),
        where: r.id not in subquery(from t in Tombstone, select: t.res_id),
        order_by: r.id,
        limit: ^limit

    query = if after_id, do: from(r in query, where: r.id > ^after_id), else: query
    Repo.all(query)
  end

  # A deep link's selector (spec-01 §9) is read before the res is looked up: a
  # selector that names no type, or one invalid at the kind's level, makes the
  # request malformed whatever the res's state.
  def show(conn, %{"id" => id}) do
    kind = conn.assigns.kind

    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, selector} <- selector(kind, conn.query_params) do
      respond(conn, kind, Lifecycle.state(uuid), selector)
    else
      :error ->
        Native.not_found(conn)

      {:invalid, reason} ->
        Native.invalid(conn, "the deep link's selector is refused: #{inspect(reason)}")
    end
  end

  defp selector(kind, params) do
    case DeepLink.read(kind, params) do
      :none -> {:ok, nil}
      {:ok, selector} -> {:ok, selector}
      {:error, reason} -> {:invalid, reason}
    end
  end

  def delete(conn, %{"id" => id}) do
    kind = conn.assigns.kind

    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:live, %Res{kind: ^kind}} <- Lifecycle.state(uuid) do
      Native.write(
        conn,
        fn -> Lifecycle.recycle(uuid, conn.assigns.principal.id) end,
        fn conn, recycling ->
          json(conn, %{
            "recycling" => recycling.id,
            "restorable_until" => recycling.purge_after,
            "contents" => Lifecycle.contents(recycling.id)
          })
        end
      )
    else
      :error -> Native.not_found(conn)
      state -> respond(conn, kind, state)
    end
  end

  defp respond(conn, kind, state), do: respond(conn, kind, state, nil)

  # A live res asked for as the interface is left to the route that renders it, which is
  # what `PluteusWeb.Representation` is reading when it decides whether to halt. Every
  # refusal below is answered here whatever was asked for, which is §10.1's one address.
  defp respond(conn, kind, {:live, %{kind: kind} = res}, nil) do
    if interface?(conn, kind),
      do: conn,
      else: json(conn, Representation.of(res, Native.profile(conn)))
  end

  # The representation names the address the link selects, with the link in
  # its canonical form.
  defp respond(conn, kind, {:live, %{kind: kind} = res}, selector) do
    address = address(kind, res, selector)

    if interface?(conn, kind),
      do: conn,
      else: json(conn, Map.put(Representation.of(res, Native.profile(conn)), "address", address))
  end

  defp respond(conn, kind, {:recycled, %{kind: kind}, recycling}, _selector) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> Problem.send(410, %{
      type: Problem.type("recycled"),
      title: "Recycled",
      detail: "In the recycle bin and restorable until the window closes.",
      restorable_until: DateTime.to_iso8601(recycling.purge_after)
    })
  end

  defp respond(conn, kind, {:purged, %{kind: kind}, tombstone}, _selector) do
    conn
    |> delete_resp_header("cache-control")
    |> Problem.send(410, %{
      type: Problem.type("purged"),
      title: "Purged",
      detail: "Permanently removed. The identifier will not be reused.",
      purged_at: DateTime.to_iso8601(tombstone.purged_at)
    })
  end

  # Absent, or present under another kind: `/works/{id}` names nothing when the
  # id belongs to an expression.
  defp respond(conn, _kind, _state, _selector), do: Native.not_found(conn)

  # Only the live-res branch forks, so the identifier, the selector, the 400, the 404 and
  # both 410s are answered in one place whatever was asked for.
  defp interface?(conn, kind), do: conn.assigns.interface? and Native.negotiates?(kind)

  defp address(kind, res, selector) do
    fields =
      Map.new(Map.delete(selector, :selector_type), fn {key, value} -> {to_string(key), value} end)

    Map.merge(fields, %{
      "type" => to_string(selector.selector_type),
      "link" => "/#{Native.paths()[kind]}/#{res.id}?#{DeepLink.query(selector)}"
    })
  end
end
