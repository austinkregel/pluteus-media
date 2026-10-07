defmodule Pluteus.Browse.EntriesTest do
  @moduledoc """
  What a browse surface lists (spec-10 §8.1, §9.3).

  The structures are built through `Pluteus.Catalog` rather than by placing files,
  because what is under test is the shape of the relations and not how ingest arrives at
  it: a release aggregating its tracks is the same shape whether it came from twelve
  files or from one with a cue sheet.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Actor
  alias Pluteus.Browse.Entries
  alias Pluteus.Browse.Query
  alias Pluteus.Catalog
  alias Pluteus.Ingest.Place
  alias Pluteus.Lifecycle

  describe "§8.1. A res is a browse entry where no other res presents it" do
    test "a holding nothing presents is an entry", %{} do
      photograph = standalone("Harbour at dawn")

      assert photograph in all()
    end

    test "a release carries the entry and its tracks do not" do
      %{release: release, tracks: tracks} = release_of("Kind of Blue", ["So What", "Freddie"])

      listed = all()

      assert release in listed

      for track <- tracks do
        refute track in listed, "a track was listed beside the release that aggregates it"
      end
    end

    test "a release is an entry although it embodies its own media, which are parts" do
      # The half of the rule that is easy to get wrong: asking that none of a work's
      # manifestations be a part would present a release by its own discs.
      %{release: release} = release_of("Bitches Brew", ["Pharaoh's Dance"])

      assert release in all()
    end

    test "a serial carries the entry and its issues do not" do
      %{serial: serial, issues: issues} = serial_of("Sandman", ["Preludes", "The Doll's House"])

      listed = all()

      assert serial in listed

      for issue <- issues do
        refute issue in listed, "an issue was listed beside the serial whose part it is"
      end
    end
  end

  describe "A work is dated by what it answers for" do
    test "a release gathering dated tracks is dated, because that is where the date is" do
      # A date is recorded against the edition its container stated it for, so a release
      # read from several files carries it on each track and not on itself. The release
      # is the entry, so a release whose date lived only on its tracks would be undated
      # on every surface that could show it.
      %{release: release, tracks: tracks} = release_of("Kind of Blue", ["So What", "Freddie"])

      for track <- tracks, do: issued(track, "1959")

      assert release in ids(%{"decade" => "1950s"})
    end

    test "a holding dated on its own manifestation is dated too" do
      photograph = standalone("Harbour at dawn")
      issued(photograph, "1964-03")

      assert photograph in ids(%{"decade" => "1960s"})
    end

    test "a holding nothing dated is in no decade" do
      standalone("Harbour at dawn")

      assert ids(%{"decade" => "1960s"}) == []
    end
  end

  describe "§14.2. What the catalog no longer holds is not listed" do
    test "a recycled entry drops out" do
      photograph = standalone("Harbour at dawn")

      assert photograph in all()

      {:ok, _} = Lifecycle.recycle(photograph, Actor.current())

      refute photograph in all()
    end
  end

  describe "§9.3. A facet narrows by the effective category, and counts sum to the total" do
    test "narrowing by a category holds the works carrying it" do
      photograph = standalone("Harbour at dawn", "photograph")
      document = standalone("A letter", "document")

      held = ids(%{"category" => "photograph"})

      assert photograph in held
      refute document in held
    end

    test "two values on one axis hold both" do
      photograph = standalone("Harbour at dawn", "photograph")
      document = standalone("A letter", "document")

      held = ids(%{"category" => "photograph,document"})

      assert photograph in held
      assert document in held
    end

    test "a corrected category is counted once, under the correction" do
      # The defect this exists to prevent: a work corrected by a member carries two
      # category rows, and matching either would put it under two categories and stop
      # the counts summing to the total.
      work = standalone("A letter", "photograph")
      {:ok, _} = Catalog.correct_category(work, Place.category_scheme(), "document")

      assert work in ids(%{"category" => "document"})
      refute work in ids(%{"category" => "photograph"})

      assert count(%{"category" => "document"}) + count(%{"category" => "photograph"}) ==
               count(%{"category" => "document,photograph"})
    end

    test "the counts of every category sum to the unnarrowed total" do
      standalone("Harbour at dawn", "photograph")
      standalone("A letter", "document")
      release_of("Kind of Blue", ["So What"])

      summed =
        Enum.sum(for category <- categories_listed(), do: count(%{"category" => category}))

      assert summed == count(%{})
    end

    test "a holding nothing has said the kind of is counted apart, not dropped" do
      # A kind is the one axis whose vocabulary is closed, so a holding without one
      # carries no value any tile could stand for. Left out of both the tiles and this
      # figure it would be in the total and in nothing that accounts for the total.
      standalone("Harbour at dawn", "photograph")
      unkinded("Blade Runner, commentary")

      summed =
        Enum.sum(for category <- categories_listed(), do: count(%{"category" => category}))

      assert summed == 1
      assert without_a_kind() == 1
      assert summed + without_a_kind() == count(%{})
    end

    test "an axis this release does not narrow on raises rather than listing everything" do
      # Built directly, because a parsed query refuses such an axis before it gets here.
      # This is the guard for the two disagreeing: an axis a query may express and
      # nothing narrows by would otherwise list everything, stating a narrowing that did
      # not happen.
      query = %Query{mode: "everything", facets: %{"language" => ["en"]}}

      assert_raise ArgumentError, ~r/not a facet axis this release narrows on/, fn ->
        Entries.count(query)
      end
    end
  end

  defp all, do: ids(%{})

  defp ids(params) do
    {:ok, query} = Query.parse("everything", params)
    Entries.ids(query, 100)
  end

  defp count(params) do
    {:ok, query} = Query.parse("everything", params)
    Entries.count(query)
  end

  defp categories_listed do
    for id <- all(),
        category = Catalog.category_of(id, Place.category_scheme()),
        uniq: true,
        do: category
  end

  defp without_a_kind do
    Repo.aggregate(from(w in Entries.without_category(Entries.base()), select: w.id), :count)
  end

  # What ingest leaves behind for a commentary stream: a work of its own embodied in the
  # film's manifestation, which nothing categorizes.
  defp unkinded(name) do
    {:ok, %{work: work}} = Catalog.create_work(%{nomen_string: name, provenance: :automatic})

    work.id
  end

  defp issued(work_id, date) do
    [expression | _rest] = Catalog.expressions_of(work_id)
    [manifestation | _more] = Catalog.manifestations_of(expression.id)

    {:ok, %{res: span}} =
      Catalog.create_named_res(:time_span, %{nomen_string: date, provenance: :automatic})

    {:ok, _} = Catalog.associate(manifestation.id, span.id, "time-of-publication-or-manufacture")

    work_id
  end

  defp standalone(name, category \\ "photograph") do
    {:ok, %{work: work}} = Catalog.create_work(%{nomen_string: name, provenance: :automatic})
    {:ok, _} = Catalog.categorize(work.id, Place.category_scheme(), category, :automatic)

    work.id
  end

  # A release as §6.4 places one: the release work's expression aggregates each track's,
  # and each track's manifestation is a part of a medium that is a part of the release.
  defp release_of(name, titles) do
    {:ok, %{work: work, expression: expression, manifestation: manifestation}} =
      Catalog.create_work(%{nomen_string: name, provenance: :automatic})

    {:ok, _} = Catalog.categorize(work.id, Place.category_scheme(), "album", :automatic)

    {:ok, %{manifestation: medium}} =
      Catalog.add_manifestation(expression.id, %{
        nomen_string: "#{name}, disc 1",
        provenance: :automatic
      })

    {:ok, _} = Catalog.add_manifestation_part(manifestation.id, medium.id, 1)

    tracks =
      for {title, position} <- Enum.with_index(titles, 1) do
        {:ok, %{work: track, expression: recording, manifestation: side}} =
          Catalog.create_work(%{nomen_string: title, provenance: :automatic})

        {:ok, _} =
          Catalog.categorize(track.id, Place.category_scheme(), "music_recording", :automatic)

        {:ok, _} = Catalog.add_manifestation_part(medium.id, side.id, position)
        {:ok, _} = Catalog.aggregate(expression.id, recording.id)

        track.id
      end

    %{release: work.id, tracks: tracks}
  end

  # A serial as §6.9 places one: the issue's own work, its manifestation a part of the
  # serial's, and the serial work taking no part of its own.
  defp serial_of(name, titles) do
    {:ok, %{work: serial, manifestation: whole}} =
      Catalog.create_work(%{nomen_string: name, provenance: :automatic})

    {:ok, _} = Catalog.categorize(serial.id, Place.category_scheme(), "comic_series", :automatic)

    issues =
      for {title, position} <- Enum.with_index(titles, 1) do
        {:ok, %{work: issue, manifestation: part}} =
          Catalog.create_work(%{nomen_string: title, provenance: :automatic})

        {:ok, _} =
          Catalog.categorize(issue.id, Place.category_scheme(), "comic_issue", :automatic)

        {:ok, _} = Catalog.add_manifestation_part(whole.id, part.id, position)

        issue.id
      end

    %{serial: serial.id, issues: issues}
  end
end
