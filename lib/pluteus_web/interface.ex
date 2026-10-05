defmodule PluteusWeb.Interface do
  @moduledoc """
  What every rendered surface needs from the request it was reached by.

  Two things, which are together here because both are per-request and neither belongs
  to any one surface:

  **The session a LiveView mounts from.** `session/1` is the shape every interface
  LiveView reads: the principal the request established, and the resolution profile the
  request resolved. A surface with more to pass adds to it rather than composing its own,
  so a key spelled one way in one caller and another way in the next cannot happen.

  **The layout and the flash.** A surface is rendered from the `:api` pipeline, which
  carries neither, because that pipeline answers the representation for the same URI and
  a JSON request has no use for a root layout or a flash. So both are put on the
  connection here, on the way to a render, rather than on every request that might not
  be one.

  Without the flash a surface can set one and have nowhere to show it, which fails
  silently: the message is in the session and no element renders it.
  """

  import Phoenix.Controller, only: [fetch_flash: 2, put_root_layout: 2]

  alias Phoenix.LiveView.Router, as: LiveRouter
  alias PluteusWeb.Native

  @doc """
  The session shape every interface LiveView mounts from.
  """
  @spec session(Plug.Conn.t()) :: %{String.t() => term()}
  def session(conn) do
    profile = Native.profile(conn)

    %{
      "principal_id" => conn.assigns.principal.id,
      "language" => profile.language,
      "assigner_id" => profile.assigner_id
    }
  end

  @doc """
  Puts the root layout and the flash on a connection that is about to render a surface.
  """
  @spec prepare(Plug.Conn.t()) :: Plug.Conn.t()
  def prepare(conn) do
    conn
    |> fetch_flash([])
    |> LiveRouter.fetch_live_flash([])
    |> put_root_layout(html: {PluteusWeb.Layouts, :root})
  end
end
