defmodule PluteusWeb.Browser.CollectionTest do
  @moduledoc """
  Criterion 28: a collection does not shift as its images arrive.

  [spec-10] §11.2 makes the means a reserved box — the ratio a probe recorded, or the one
  §20 assumes for the category — so a tile's size is settled before its image is fetched.
  Whether that holds is a property of the laid-out page, not of the markup asking for it:
  a style attribute can say `aspect-ratio` while something around it lets the image push
  the row taller anyway. So this measures every tile as the document first stands, before
  any image has loaded, and again once every image has, and asserts nothing moved.

  The photographs are of three shapes, so the justified grid's rows are made of unequal
  tiles and the residual row carries a filler. A collection of one shape would hold still
  under rules that a mixed one exposes.
  """

  use PluteusWeb.BrowserCase

  import Pluteus.IngestFixtures

  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Presentation.Generate
  alias Pluteus.Repo
  alias Pluteus.Storage

  # Wide, tall, and the fixture's own 4:3, so a row holds tiles of three widths.
  @shapes ~w(96x48 48x64 64x48 64x48 48x64)

  @measured """
  return [...document.querySelectorAll("[id^='tile-']")].map((t) => {
    const r = t.getBoundingClientRect();
    const img = t.querySelector("img");
    return {id: t.id, x: r.x + window.scrollX, y: r.y + window.scrollY,
            width: r.width, height: r.height,
            arrived: !!(img && img.complete && img.naturalWidth > 0)};
  });
  """

  setup do
    %{photographs: photographs()}
  end

  describe "28. A collection does not shift as its images arrive" do
    test "every tile stands where it stood before any image loaded",
         %{photographs: photographs} do
      # Tall enough that no tile is below the fold, since a lazy image there would never
      # arrive and the comparison would be of a page still waiting.
      browser = open!("/notices", height: 1600)

      Browser.on_every_document(browser, """
      document.addEventListener("DOMContentLoaded", () => {
        window.__before = (() => { #{@measured} })();
      });
      """)

      Browser.go(browser, Proxy.url("/everything?category=photograph"))

      Browser.await(browser, """
      const images = [...document.querySelectorAll("[id^='tile-'] img")];
      return images.length === #{length(photographs)} &&
        images.every((i) => i.complete && i.naturalWidth > 0);
      """)

      before = Browser.evaluate(browser, "return window.__before")
      after_arrival = Browser.evaluate(browser, @measured)

      assert Enum.map(before, & &1["id"]) |> Enum.sort() ==
               photographs |> Enum.map(&"tile-#{&1}") |> Enum.sort()

      # The comparison says nothing if the images had already arrived when the page was
      # first measured, so at least one must have been still to come.
      assert Enum.any?(before, &(not &1["arrived"])),
             "every image had arrived before the page was first measured, so nothing " <>
               "was watched arriving"

      assert Enum.all?(after_arrival, & &1["arrived"])

      box = ~w(x y width height)

      moved =
        for {first, last} <- Enum.zip(before, after_arrival),
            Enum.any?(box, &(abs(first[&1] - last[&1]) > 0.5)),
            do: {first["id"], Map.take(first, box), Map.take(last, box)}

      assert moved == [], "tiles moved as their images arrived: #{inspect(moved)}"
    end
  end

  # Photographs placed from the inbox, each with the derivative the grid asks for already
  # made, so what loads is the image a person would see rather than an absence.
  defp photographs do
    inbox = inbox!()
    prefix = unique_prefix()

    for {size, index} <- Enum.with_index(@shapes, 1) do
      drop!(inbox, "#{prefix}/photos/holiday/IMG_000#{index}.png", media!(:png, size: size))
    end

    ids = inbox |> acquire_settled!() |> acquired()
    place_all!(inbox)
    Normalize.normalize_due()

    for id <- ids do
      acquisition = Ingest.get_acquisition!(id)
      manifestation = Repo.get!(DigitalItem, acquisition.digital_item_id).manifestation_id

      {:ok, made} = Generate.run(manifestation, "image-640")
      on_exit(fn -> Storage.delete(made.location) end)

      work_of(manifestation)
    end
  end

  defp work_of(manifestation) do
    [expression | _rest] = Pluteus.Catalog.expressions_in(manifestation)
    expression.work_id
  end
end
