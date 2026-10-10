defmodule PluteusWeb.Live.Identity do
  @moduledoc """
  Establishes the principal a LiveView is rendering for, on both of its mounts.

  There are two, and they have different evidence. The dead render is the request's,
  which `PluteusWeb.ForwardAuth` has already established, and it carries the principal
  in the session. The connected mount is a socket, whose only identity is the proxy's
  headers, so it establishes the principal again from those.

  Where the two disagree the mount raises, because the alternative is one document
  showing one principal's page over another principal's connection — and spec-10 §14.3
  makes that the thing a surface may never do.

  Declared by `PluteusWeb.surface/0` rather than in a `live_session`, so it runs however
  the surface was rendered. `PluteusWeb.EntityLive` is `live_render`ed from a controller
  and belongs to no live session; declaring the hook in the module it is used from is
  what gives it the same contract as a surface reached by a `live` route.

  A LiveView nested inside a surface does not declare it: it has no connection of its
  own to establish anything against.

  A session carrying no principal raises rather than mounting anonymously. Every
  surface spec-10 §9 names is the requesting principal's, and the two household-public
  pages — the licence notices and §4.4's question — are rendered by a controller and
  mount nothing.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [get_connect_info: 2]

  alias PluteusWeb.ForwardAuth

  @doc """
  Assigns `:principal_id`, having established it from whichever evidence the mount has.
  """
  def on_mount(:default, _params, session, socket) do
    held = Map.fetch!(session, "principal_id")

    {:cont, assign(socket, :principal_id, established!(socket, held))}
  end

  # A dead render has no connect info, so the session's principal stands: the request it
  # came from passed through forward authentication to get here.
  defp established!(socket, held) do
    case get_connect_info(socket, :x_headers) do
      nil ->
        held

      headers ->
        agreed!(ForwardAuth.principal(headers), held)
    end
  end

  defp agreed!({:ok, %{id: held}}, held), do: held

  defp agreed!({:ok, %{id: other}}, held) do
    raise "the socket is #{other}'s and the page is #{held}'s"
  end

  defp agreed!({:error, type, detail}, _held) do
    raise "the socket carries no principal: #{type}, #{detail}"
  end
end
