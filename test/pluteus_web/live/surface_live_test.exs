defmodule PluteusWeb.SurfaceLiveTest do
  @moduledoc """
  The surface a holding's category is presented on (spec-10 §12.1, §10.1, §11.2).

  What is asserted here is the boundary rather than the drawing: that a path beneath a
  res reaches the surface its category names and nothing else, that the four refusals
  are refusals, and that a player reserves a box before any byte of the medium arrives.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Ingest.Place
  alias Pluteus.Lifecycle
  alias Pluteus.Principals
  alias Pluteus.Surfaces.Registry, as: Surfaces

  setup %{conn: conn} do
    %{conn: conn |> through_proxy(a_subject()) |> on_a_surface()}
  end

  describe "§12.1, §10.1. A category is presented beneath the address its res has" do
    test "a holding played reaches the player", %{conn: conn} do
      film = named("Duck and Cover", "home_video")

      {:ok, _live, html} = live(conn, ~p"/works/#{film}/play")

      assert html =~ "Duck and Cover"
      assert html =~ ~s|id="player-picture"| or html =~ ~s|id="player-refusal"|
    end

    test "a holding read reaches the reader", %{conn: conn} do
      letter = named("A letter", "document")

      {:ok, _live, html} = live(conn, ~p"/works/#{letter}/read")

      assert html =~ "A letter"
      assert html =~ "presented on a reader"
    end

    # Every segment the router carries comes from the registry, so a category named
    # there and addressed nowhere would be a route to nothing.
    test "every segment the router builds is one a category is presented at" do
      addressed = Surfaces.surfaces()

      for category <- Surfaces.presented_categories(),
          surface = Surfaces.surface_of(category),
          surface != nil do
        assert surface in addressed,
               "#{category} is presented at #{surface}, which the router does not build"
      end

      assert addressed == ["play", "read", "view"]
    end
  end

  describe "§10.1. A path beneath a res refuses what it does not name" do
    test "an identifier that is not one is not found", %{conn: conn} do
      assert_raise PluteusWeb.NotFoundError, ~r/is not an identifier/, fn ->
        live(conn, ~p"/works/not-a-uuid/play")
      end
    end

    test "a work nobody holds is not found", %{conn: conn} do
      assert_raise PluteusWeb.NotFoundError, ~r/no holding is held/, fn ->
        live(conn, ~p"/works/#{Ecto.UUID.generate()}/play")
      end
    end

    test "a surface the category is not presented on is not found", %{conn: conn} do
      film = named("Duck and Cover", "home_video")

      assert_raise PluteusWeb.NotFoundError, ~r/not presented/, fn ->
        live(conn, ~p"/works/#{film}/read")
      end
    end

    # The identifier stays refused rather than becoming someone else's, so this is not
    # the same answer as a work nobody holds.
    test "a recycled holding is gone, not absent", %{conn: conn} do
      film = named("Duck and Cover", "home_video")
      {:ok, principal} = Principals.create_principal(%{role: "member"})
      {:ok, _recycling} = Lifecycle.recycle(film, principal.id)

      assert_raise PluteusWeb.GoneError, ~r/recycle bin/, fn ->
        live(conn, ~p"/works/#{film}/play")
      end
    end
  end

  describe "§11.2. A player reserves its box before the medium arrives" do
    # A page that reflows as its medium loads moves what a person was reaching for. The
    # holding here has no bytes at all, so what is reserved is §20's own figure for the
    # category and not a measurement.
    test "a holding nothing has probed still reserves the category's ratio",
         %{conn: conn} do
      film = named("Duck and Cover", "home_video")

      {:ok, _live, html} = live(conn, ~p"/works/#{film}/play")

      assert html =~ "aspect-ratio: 1.7778"
    end

    test "a holding with no file says so inside the box it reserved", %{conn: conn} do
      film = named("Duck and Cover", "home_video")

      {:ok, _live, html} = live(conn, ~p"/works/#{film}/play")

      assert html =~ ~s|id="player-refusal"|
      assert html =~ "holds no file for it"
    end
  end

  defp named(name, category) do
    {:ok, %{work: work}} = Catalog.create_work(%{nomen_string: name, provenance: :automatic})
    {:ok, _} = Catalog.categorize(work.id, Place.category_scheme(), category, :automatic)

    work.id
  end
end
