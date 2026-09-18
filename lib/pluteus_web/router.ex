defmodule PluteusWeb.Router do
  use PluteusWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PluteusWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug PluteusWeb.ForwardAuth
  end

  pipeline :onboarding do
    plug :accepts, ["json"]
    plug PluteusWeb.ForwardAuth, require_principal: false
  end

  scope "/", PluteusWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/", PluteusWeb do
    pipe_through :onboarding

    post "/onboarding", OnboardingController, :create
  end

  # §9.1's entity URIs. The kind is fixed by the path, so an identifier
  # belonging to another kind is not found here rather than redirected.
  scope "/", PluteusWeb do
    pipe_through :api

    get "/works/:id", EntityController, :show, assigns: %{kind: :work}
    get "/expressions/:id", EntityController, :show, assigns: %{kind: :expression}
    get "/manifestations/:id", EntityController, :show, assigns: %{kind: :manifestation}
    get "/items/:id", EntityController, :show, assigns: %{kind: :item}
    get "/digital-items/:id", EntityController, :show, assigns: %{kind: :digital_item}
    get "/assets/:id", EntityController, :show, assigns: %{kind: :asset}
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
