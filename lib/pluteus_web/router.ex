defmodule PluteusWeb.Router do
  use PluteusWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PluteusWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers

    # A rendered surface may answer with no principal — the design language and the
    # licence notices are the household's — so identity is attached where the proxy
    # named one rather than required of every request. Contexts follows it, because
    # spec-10 §14.5's preferences are read per principal or not at all.
    plug PluteusWeb.Identify
    plug PluteusWeb.Contexts
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug PluteusWeb.ForwardAuth
  end

  # spec-07 §3.2: the one surface exempt from forward authentication, where a
  # client key is the request's authentication. The request must still have
  # come through the proxy.
  pipeline :subsonic do
    plug PluteusWeb.Subsonic.Authenticate
  end

  pipeline :onboarding do
    plug :accepts, ["json"]
    plug PluteusWeb.ForwardAuth, require_principal: false
  end

  scope "/", PluteusWeb do
    pipe_through :browser

    get "/", PageController, :home

    # spec-10 Annex A.8.1 puts half of the vendored glyph set's licence obligation
    # beside the files and the other half in the interface, so this route is what the
    # licence requires rather than a courtesy.
    get "/notices", PageController, :notices
  end

  scope "/", PluteusWeb do
    pipe_through :onboarding

    post "/onboarding", OnboardingController, :create
  end

  # §9.1's entity URIs. The kind is fixed by the path, so an identifier
  # belonging to another kind is not found here rather than redirected.
  scope "/", PluteusWeb do
    pipe_through :api

    for {kind, path} <- PluteusWeb.Native.paths() do
      get "/#{path}", EntityController, :index, assigns: %{kind: kind}
      get "/#{path}/:id", EntityController, :show, assigns: %{kind: kind}
      delete "/#{path}/:id", EntityController, :delete, assigns: %{kind: kind}
      post "/#{path}/:id/categories", WriteController, :categorize, assigns: %{kind: kind}

      # [spec-10] §11.1. Inside this comprehension so the kind stays fixed by the
      # path, as §9.1 requires of every entity URI.
      get "/#{path}/:id/presentation/:profile", PresentationController, :show,
        assigns: %{kind: kind}

      # §11.2's tiled pyramid, under the IIIF Image API grammar. The grammar's own
      # segments are the route, so a viewer that already speaks it needs to know
      # nothing about this deployment but the identifier.
      get "/#{path}/:id/iiif/info.json", IiifController, :information, assigns: %{kind: kind}

      get "/#{path}/:id/iiif/:region/:size/:rotation/:quality", IiifController, :tile,
        assigns: %{kind: kind}
    end

    get "/assets/:id/content", ContentController, :show

    post "/nomens", WriteController, :create_nomen
    post "/annotations", WriteController, :annotate
    post "/duplicate-candidates/:id/decision", WriteController, :decide
    post "/recyclings/:id/restoration", WriteController, :restore
    delete "/recyclings/:id", WriteController, :empty

    get "/changes", ChangeController, :index

    # §11.2's platform class, which every member reads. The consumption class has
    # no route: §11.3 forbids the two to share a representation, and each
    # principal reaches its own consumption through its own surfaces.
    get "/platform-events", PlatformEventController, :index

    get "/findings", FindingController, :index
    get "/findings/:id", FindingController, :show
    post "/findings/:id/clearing", WriteController, :clear_finding

    get "/devices", DeviceController, :index
    post "/devices", DeviceController, :create
    delete "/devices/:id", DeviceController, :delete

    # [spec-10] §14.5's preferences, which are the requesting principal's and no
    # other's. The path carries no principal, so there is no request that names
    # another's and none to refuse — which spec-07 §4.5 makes the point: a refusal
    # would itself confirm what it refused.
    get "/preferences", PreferenceController, :index
    put "/preferences", PreferenceController, :update
  end

  scope "/rest", PluteusWeb do
    pipe_through :subsonic

    get "/:endpoint", SubsonicController, :dispatch
    post "/:endpoint", SubsonicController, :dispatch
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:pluteus, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PluteusWeb.Telemetry
    end
  end
end
