defmodule PluteusWeb.Representation do
  @moduledoc """
  Answers an entity URI's representation before the route it shares is reached.

  spec-10 §10.1 gives a res one address answering two things: the interface where the
  request asks for HTML, and spec-07 §4.1's representation otherwise. A route dispatches
  to one place, so the fork is here — the representation is answered and the request
  halted, leaving the route itself to the interface.

  That is what lets the interface be a `live` route, which is what lets a person reach a
  holding without the page being torn down and rebuilt around them.

  Only a path naming a kind and an identifier is forked on. A mode is not a res, and a
  surface beneath a res answers no representation at all (§10.1), so neither is touched.
  """

  import Plug.Conn

  alias PluteusWeb.EntityController
  alias PluteusWeb.Native

  def init(opts), do: opts

  def call(conn, _opts) do
    case kind_of(conn.path_info) do
      nil -> conn
      kind -> forked(assign(conn, :kind, kind), kind)
    end
  end

  # The refusals are the controller's whatever was asked for, so they answer as problem
  # documents here rather than as an error page on the way to a route. What it leaves
  # unsent is a live res asked for as the interface, which the route renders.
  defp forked(conn, _kind) do
    case EntityController.show(conn, conn.path_params) do
      %Plug.Conn{state: :unset} = conn -> conn
      answered -> halt(answered)
    end
  end

  defp kind_of([path, _id]) do
    Enum.find_value(Native.paths(), fn {kind, kind_path} -> kind_path == path and kind end)
  end

  defp kind_of(_not_an_entity_uri), do: nil
end
