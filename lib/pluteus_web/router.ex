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
    plug PluteusWeb.Surface
  end

  # spec-07 §4.1: an entity URI answers with the interface where the request's `Accept`
  # contains `text/html` and with the representation otherwise, at the same URI under the
  # same authorization. `Negotiate` decides which before the session is read, and the
  # session is read before the principal because it is what carries one to the socket.
  pipeline :api do
    plug :accepts, ["json", "html"]
    plug PluteusWeb.Negotiate
    plug :fetch_session
    plug PluteusWeb.ForwardAuth
    plug PluteusWeb.Surface
  end

  # Every surface spec-10 §9 names is the requesting principal's own, so identity is
  # required here rather than attached where the proxy happened to name one: §9.2's
  # Continue is a principal's resume list and §14.1 makes every surface state who it is
  # acting as. `ForwardAuth` refuses a request carrying no principal, which `Identify`
  # on the `:browser` pipeline deliberately does not, because the design language and the
  # licence notices are the household's.
  #
  # Unlike `:api` this answers only HTML: a browse mode is not a res and has no
  # representation to negotiate for.
  pipeline :interface do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PluteusWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug PluteusWeb.ForwardAuth
    plug PluteusWeb.Contexts
    plug PluteusWeb.Surface
    plug PluteusWeb.Declared

    # After `Declared`, so a request that is about to be sent away to declare a surface
    # does not enrol a device on the way.
    plug PluteusWeb.Device
  end

  # An entity URI, which answers both things §10.1 names. `Representation` answers the
  # representation and halts; what survives it is a request for the interface, and the
  # rest of this is `:interface`'s, so the page is a route of the same live session as
  # every other surface.
  pipeline :entity do
    plug :accepts, ["json", "html"]
    plug PluteusWeb.Negotiate
    plug :fetch_session
    plug PluteusWeb.ForwardAuth
    plug PluteusWeb.Surface
    plug PluteusWeb.Representation

    plug :fetch_live_flash
    plug :put_root_layout, html: {PluteusWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug PluteusWeb.Contexts
    plug PluteusWeb.Declared
    plug PluteusWeb.Device
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

    # The design language, rendered. It is not at `/`, which is the catalogue's own
    # address: a reference for the people building the interface is not what a person
    # opening the deployment is looking for.
    get "/design", PageController, :home

    # spec-10 Annex A.8.1 puts half of the vendored glyph set's licence obligation
    # beside the files and the other half in the interface, so this route is what the
    # licence requires rather than a courtesy.
    get "/notices", PageController, :notices

    # [spec-10] §4.4's declaration. A surface is not a res, so §10.1 gives it a path of
    # its own rather than this being a second address for something that has one.
    get "/surface", SurfaceController, :ask
    post "/surface", SurfaceController, :declare
  end

  scope "/", PluteusWeb do
    pipe_through :onboarding

    post "/onboarding", OnboardingController, :create
  end

  # §9.2's modes. One LiveView answers every mode with the mode as its `live_action`, so a
  # mode gaining a surface is a route rather than another page. Only the one that has a
  # surface has a route: a route to an unbuilt one would answer nothing, and the chrome
  # renders the other six disabled carrying the reason instead (§17.3).
  #
  # The live session carries only the session shape `PluteusWeb.Interface` owns. The
  # identity hook is declared by `PluteusWeb.surface/0` rather than here, so it holds
  # however a surface was reached.
  #
  # Every interface surface is in this one session, which is what makes moving between
  # them a live navigation rather than a page load — and so what keeps the transport
  # playing while a person goes from a mode to a holding to its player.
  live_session :interface, session: {PluteusWeb.Interface, :session, []} do
    scope "/", PluteusWeb do
      pipe_through :interface

      live "/everything", BrowseLive, :everything

      # §12.1's primary surfaces, addressed beneath the work whose category names them
      # (§10.1). Under the work because a category is the work's.
      #
      # A segment here that no category is presented at would be a route to nothing, so
      # the list is the registry's rather than this file's.
      for surface <- PluteusWeb.Native.surfaces() do
        live "/works/:id/#{surface}", SurfaceLive, :"#{surface}"
      end
    end

    # §9.1's entity URIs, for the kinds that answer an interface. The representation is
    # answered by the pipeline and halted there, so what reaches these is a request for
    # the page. The kind is fixed by the path, as §9.1 requires.
    scope "/", PluteusWeb do
      pipe_through :entity

      for {kind, path} <- PluteusWeb.Native.paths(), PluteusWeb.Native.negotiates?(kind) do
        live "/#{path}/:id", EntityLive, :show
      end

      # §16.1 puts this on every surface, so it is reached from the chrome without the
      # page being torn down. spec-07 §4.1 makes it a resource too, which the pipeline
      # answers before this route is reached.
      live "/findings", FindingsLive, :index
    end
  end

  # §9.1's entity URIs. The kind is fixed by the path, so an identifier
  # belonging to another kind is not found here rather than redirected.
  scope "/", PluteusWeb do
    pipe_through :api

    for {kind, path} <- PluteusWeb.Native.paths() do
      get "/#{path}", EntityController, :index, assigns: %{kind: kind}

      # A kind §9.1 names has its one address above, where the representation is
      # answered by the pipeline and the page by the route. A kind that answers no
      # interface has only the representation, so it keeps its own route.
      unless PluteusWeb.Native.negotiates?(kind) do
        get "/#{path}/:id", EntityController, :show, assigns: %{kind: kind}
      end

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

    # The index is both a resource and §16.1's surface, so it shares one address the way
    # an entity URI does and the pipeline answers the representation. One finding is a
    # resource and nothing else, so it keeps its own route.
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
