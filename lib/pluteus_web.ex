defmodule PluteusWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use PluteusWeb, :controller
      use PluteusWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  @doc """
  A LiveView a request reaches directly, which establishes the principal it renders for.

  Declared by the surface rather than by a `live_session`, so it runs however the surface
  was rendered: `PluteusWeb.EntityLive` is `live_render`ed from a controller and belongs
  to no live session.

  A LiveView nested inside a surface does not declare it. It has no connection of its
  own to establish anything against, and its session is the one its parent handed down
  after establishing the principal on the connection they share.

  Every surface draws the chrome, and with it the search field, so every surface answers
  that field's submission through `PluteusWeb.Live.Search`.
  """
  def surface do
    quote do
      use PluteusWeb, :live_view

      on_mount PluteusWeb.Live.Identity
      on_mount PluteusWeb.Live.Search
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components
      import PluteusWeb.CoreComponents
      # The vendored glyph set, drawn inline (Annex A.8)
      import PluteusWeb.Icon

      # Common modules used in templates
      alias Phoenix.LiveView.JS
      alias PluteusWeb.Layouts

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: PluteusWeb.Endpoint,
        router: PluteusWeb.Router,
        statics: PluteusWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
