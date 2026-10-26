defmodule Pluteus.Browse.SearchTest do
  @moduledoc """
  What a search reaches and how its results are told apart ([spec-10] §9.5, §6.2, §6.4).
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Browse
  alias Pluteus.Browse.Query
  alias Pluteus.Browse.Search
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Profile
  alias Pluteus.Ingest.Place
  alias Pluteus.MusicFixtures
  alias Pluteus.Principals
  alias Pluteus.Surfaces.Registry, as: Surfaces

  setup do
    {:ok, principal} = Principals.create_principal(%{role: "member"})

    %{principal: principal}
  end

  describe "§9.5. The search matches every nomen a res carries" do
    test "a holding is reached by its own name, and says nothing more", %{principal: principal} do
      novel = named("Pride and Prejudice #{unique()}", "ebook")

      surface = searched(principal, "pride and")

      assert novel in surface.entries
      assert Search.matched_through(surface.matched[novel], surface.names[novel]) == nil
    end

    test "a holding is reached by any of its names, not only the one it is shown by",
         %{principal: principal} do
      title = "Le Petit Prince #{unique()}"
      book = named(title, "ebook")
      {:ok, _} = Catalog.create_nomen(%{res_id: book, nomen_string: "The Little Prince"})

      surface = searched(principal, "little prince")

      assert book in surface.entries
    end

    test "a match is containment, ignoring case, and takes wildcards literally",
         %{principal: principal} do
      suffix = unique()
      pure = named("100% Pure #{suffix}", "album")
      thousand = named("1000 Pure #{suffix}", "album")

      surface = searched(principal, "100% PURE")

      assert pure in surface.entries
      refute thousand in surface.entries
    end

    test "a release is reached by a track it gathers and by who it credits",
         %{principal: principal} do
      library = MusicFixtures.library!()
      release = Catalog.work_of(library.albums["01 So What.flac"])

      by_track = searched(principal, "freddie freeloader")
      by_artist = searched(principal, library.artist)

      assert release in by_track.entries
      assert release in by_artist.entries
    end
  end

  # Criterion 13: "A search matching a nomen other than the displayed one returns a result
  # stating which nomen matched."
  describe "13. A result reached through another name says which name it was" do
    test "the track's name is the one the release is said to have matched",
         %{principal: principal} do
      library = MusicFixtures.library!()
      release = Catalog.work_of(library.albums["01 So What.flac"])

      surface = searched(principal, "freddie")

      assert surface.names[release] == "Kind of Blue"

      assert Search.matched_through(surface.matched[release], surface.names[release]) ==
               "Freddie Freeloader"
    end
  end

  describe "§7.3. One person's word for a thing stays with that person" do
    test "a personal name matches for the person it belongs to and nobody else",
         %{principal: principal} do
      {:ok, %{res: person}} =
        Catalog.create_named_res(:person, %{nomen_string: "Ada", provenance: :local})

      book = named("Persuasion #{unique()}", "ebook")
      label = "grandmother's copy #{unique()}"

      {:ok, _} =
        Catalog.create_nomen(%{
          res_id: book,
          nomen_string: label,
          assigner_id: person.id,
          provenance: :local
        })

      assert book in searched(principal, label, %Profile{assigner_id: person.id}).entries
      refute book in searched(principal, label, %Profile{}).entries
    end
  end

  describe "§9.5. A query is one more term over the current selection" do
    test "the facets narrow what the term reaches", %{principal: principal} do
      name = "Emma #{unique()}"
      book = named(name, "ebook")
      film = named(name, "film")

      surface = searched(principal, name, %Profile{}, %{"category" => "film"})

      assert surface.entries == [film]
      refute book in surface.entries
    end

    test "the total is of the search and the whole is of the mode it searched",
         %{principal: principal} do
      named("Middlemarch #{unique()}", "ebook")

      surface = searched(principal, "middlemarch")

      assert surface.total == 1
      assert surface.catalogue >= surface.total
    end
  end

  describe "§6.4. Results are ordered by name, and say by which" do
    test "with no ordering name recorded they go by their resolved names",
         %{principal: principal} do
      suffix = unique()
      zola = named("Zola #{suffix}", "ebook")
      austen = named("austen #{suffix}", "ebook")

      surface = searched(principal, suffix)

      assert surface.entries == [austen, zola]
      assert surface.ordering == :resolved
    end

    test "an ordering name, where one is recorded, decides that result's place",
         %{principal: principal} do
      suffix = unique()
      beatles = named("The Beatles #{suffix}", "album")
      abba = named("Abba #{suffix}", "album")

      {:ok, _} =
        Catalog.create_nomen(%{
          res_id: beatles,
          nomen_string: "Beatles, The",
          scheme: Surfaces.ordering_scheme()
        })

      surface = searched(principal, suffix)

      assert surface.entries == [abba, beatles]
      assert surface.ordering == :mixed
    end
  end

  # Criterion 14: "Two res resolving to one string for one profile are each rendered with a
  # disambiguator."
  describe "14. Results shown by one name are each told apart" do
    test "by what kind of thing each is, where that differs", %{principal: principal} do
      name = "Wuthering Heights #{unique()}"
      book = named(name, "ebook")
      film = named(name, "film")

      alike = searched(principal, name).alike

      assert alike[book] == "an ebook"
      assert alike[film] == "a film"
    end

    test "and say so where nothing recorded tells them apart", %{principal: principal} do
      name = "Jane Eyre #{unique()}"
      one = named(name, "ebook")
      two = named(name, "ebook")

      alike = searched(principal, name).alike

      assert alike[one] == "nothing recorded tells these 2 apart"
      assert alike[two] == "nothing recorded tells these 2 apart"
    end

    test "a result whose name is its own carries none", %{principal: principal} do
      own = named("Villette #{unique()}", "ebook")

      refute Map.has_key?(searched(principal, "villette").alike, own)
    end
  end

  defp searched(principal, term, profile \\ %Profile{}, params \\ %{}) do
    {:ok, query} = Query.parse_search(Map.put(params, "q", term))

    Browse.surface(query, principal.id, profile)
  end

  defp named(name, category) do
    {:ok, %{work: work}} = Catalog.create_work(%{nomen_string: name, provenance: :automatic})
    {:ok, _} = Catalog.categorize(work.id, Place.category_scheme(), category, :automatic)

    work.id
  end

  defp unique, do: "n#{System.unique_integer([:positive])}"
end
