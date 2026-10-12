defmodule PluteusWeb.Interface do
  @moduledoc """
  What every rendered surface needs from the request it was reached by.

  Two things, which are together here because both are per-request and neither belongs
  to any one surface:

  **The session a LiveView mounts from.** `session/1` is the shape every interface
  LiveView reads: the principal the request established, the resolution profile the
  request resolved, the context intents the chrome's controls render their pressed state
  from, and the device the browser is. A surface with more to pass adds to it rather than
  composing its own, so a key spelled one way in one caller and another way in the next
  cannot happen.

  The device may be absent, and why is carried with it: a LiveView cannot mint one,
  because a socket is not the request that holds the cookie, and a transport with nothing
  to key a position by has to say that rather than discard what it reports.

  The contexts travel in the session rather than being read at mount, because the
  controls have to state the person's own choice in the first paint: a mount that fetched
  them would render the page once without them and correct it after.

  **The layout, the flash and the forgery token.** A surface is rendered from the `:api`
  pipeline, which carries none of them, because that pipeline answers the representation
  for the same URI and a JSON request has no use for a root layout or a flash. So they
  are put on the connection here, on the way to a render, rather than on every request
  that might not be one — and the forgery plug cannot go on the pipeline itself, where it
  would start refusing the writes that same pipeline serves.

  Without the flash a surface can set one and have nowhere to show it, which fails
  silently: the message is in the session and no element renders it.

  Without the forgery token the session holds nothing to verify the token in the page
  against, so a live socket's join is refused as misconfigured and the client recovers by
  reloading — which lands on the same page, and reloads again.
  """

  import Phoenix.Controller, only: [fetch_flash: 2, protect_from_forgery: 2, put_root_layout: 2]

  alias Phoenix.LiveView.Router, as: LiveRouter
  alias PluteusWeb.Contexts
  alias PluteusWeb.Native

  @doc """
  The session shape every interface LiveView mounts from.

  **Everything here is the principal's or the device's, and nothing here is the page's.**
  This is built once, by the request that establishes the socket, and a live navigation to
  another surface does not build it again — so a value that belongs to one address would
  be answered to every address reached after it. What belongs to an address is read from
  the address, in `handle_params`, which is what runs when the address changes.
  """
  @spec session(Plug.Conn.t()) :: %{String.t() => term()}
  def session(conn) do
    profile = Native.profile(conn)

    %{
      "principal_id" => conn.assigns.principal.id,
      "language" => profile.language,
      "assigner_id" => profile.assigner_id,
      "contexts" => Contexts.held_by(conn.assigns.principal),
      "device_id" => conn.assigns[:device_id],
      "device_revoked" => conn.assigns[:device_revoked]
    }
  end

  @doc """
  The session the player mounts from.

  The player is a LiveView of its own rendered sticky, so it does not take what a
  surface was handed: it is not torn down with one and would outlive the hand-down.
  """
  @spec transport(%{String.t() => term()}) :: %{String.t() => term()}
  def transport(session) do
    Map.take(session, ~w(principal_id language assigner_id device_id device_revoked))
  end

  @doc """
  Puts the root layout and the flash on a connection that is about to render a surface.
  """
  @spec prepare(Plug.Conn.t()) :: Plug.Conn.t()
  def prepare(conn) do
    conn
    |> fetch_flash([])
    |> LiveRouter.fetch_live_flash([])
    |> protect_from_forgery([])
    |> put_root_layout(html: {PluteusWeb.Layouts, :root})
  end
end
