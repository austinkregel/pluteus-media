defmodule PluteusWeb.EntityController do
  @moduledoc """
  Serves an entity at the URI §9.1 gives it, answering for its lifecycle state
  as §14.2 requires.

  A recycled entity is `410 Gone` with `Cache-Control: no-store`. 410 is
  cacheable by default, and a cached tombstone would outlive a restore; the
  problem body says when the window closes so a client can offer to restore
  it. A purged entity is `410 Gone` too, with default cacheability left in
  place, because its permanence is then accurate.
  """

  use PluteusWeb, :controller

  alias Pluteus.Lifecycle
  alias PluteusWeb.Problem

  def show(conn, %{"id" => id}) do
    kind = conn.assigns.kind

    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> respond(conn, kind, Lifecycle.state(uuid))
      :error -> not_found(conn)
    end
  end

  defp respond(conn, kind, {:live, %{kind: kind} = res}) do
    json(conn, %{id: res.id, kind: res.kind})
  end

  defp respond(conn, kind, {:recycled, %{kind: kind}, recycling}) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> Problem.send(410, %{
      type: Problem.type("recycled"),
      title: "Recycled",
      detail: "In the recycle bin and restorable until the window closes.",
      restorable_until: DateTime.to_iso8601(recycling.purge_after)
    })
  end

  defp respond(conn, kind, {:purged, %{kind: kind}, tombstone}) do
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
  defp respond(conn, _kind, _state), do: not_found(conn)

  defp not_found(conn) do
    Problem.send(conn, 404, %{type: "about:blank", title: "Not Found"})
  end
end
