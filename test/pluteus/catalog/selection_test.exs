defmodule Pluteus.Catalog.SelectionTest do
  @moduledoc """
  spec-01 §8.6 and [spec-10] §8.1: which expression a principal is given, and how many
  others there were.

  §8.1 requires the resolution happen without asking, so what is asserted here is the order
  the three answers come in — what the principal chose, what they prefer, what the work is —
  and that the count of alternatives is stated.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Representative
  alias Pluteus.Catalog.Selection
  alias Pluteus.Ingest.Place
  alias Pluteus.Preferences
  alias Pluteus.Principals

  setup do
    {:ok, principal} = Principals.create_principal(%{role: "member"})

    %{principal: principal, profile: %Profile{}}
  end

  defp a_film_in_two_languages do
    {:ok, %{work: work, expression: russian, manifestation: manifestation}} =
      Catalog.create_work(%{nomen_string: "The Dig", language: "ru"})

    {:ok, _category} = Catalog.categorize(work.id, Place.category_scheme(), "film", :automatic)

    {:ok, %{expression: english}} =
      Catalog.add_expression_embodied_in(work.id, manifestation.id, %{
        nomen_string: "The Dig",
        language: "en"
      })

    %{work: work, russian: russian, english: english}
  end

  describe "§8.1. The action resolves without asking" do
    test "a work with one expression answers it and no alternatives", %{
      principal: principal,
      profile: profile
    } do
      {:ok, %{work: work, expression: only}} = Catalog.create_work("Kind of Blue")

      assert %{expression: chosen, alternatives: 0, by: :only} =
               Selection.for_principal(work.id, principal.id, profile)

      assert chosen.id == only.id
    end

    test "a work with two expressions states that there is one alternative", %{
      principal: principal,
      profile: profile
    } do
      %{work: work} = a_film_in_two_languages()

      assert %{alternatives: 1} = Selection.for_principal(work.id, principal.id, profile)
    end

    test "a work the household holds no file for has nothing to act on", %{
      principal: principal,
      profile: profile
    } do
      # spec-01 §5.2: zero digital items is a work the household describes and holds no file
      # for. The expression still resolves; §8.1's action has nothing to act on.
      {:ok, %{work: work}} = Catalog.create_work("A film nobody has")

      assert %{digital_item: nil} = Selection.for_principal(work.id, principal.id, profile)
    end

    test "a work with no expression raises rather than answering nothing", %{
      principal: principal,
      profile: profile
    } do
      {:ok, %{res: work}} = Catalog.create_named_res(:work, "An empty work")

      assert_raise ArgumentError, fn ->
        Selection.for_principal(work.id, principal.id, profile)
      end
    end
  end

  describe "what the principal chose comes first" do
    test "a recorded choice outranks the preference and the distance", %{
      principal: principal,
      profile: profile
    } do
      %{work: work, russian: russian, english: english} = a_film_in_two_languages()
      {:ok, _set} = Preferences.set(principal.id, "audio_language", "en")
      {:ok, _chosen} = Selection.choose(principal.id, work.id, russian.id)

      assert %{expression: answered, by: :chosen} =
               Selection.for_principal(work.id, principal.id, profile)

      assert answered.id == russian.id
      refute answered.id == english.id
    end

    test "choosing again replaces the answer", %{principal: principal, profile: profile} do
      %{work: work, russian: russian, english: english} = a_film_in_two_languages()

      {:ok, _first} = Selection.choose(principal.id, work.id, russian.id)
      {:ok, _second} = Selection.choose(principal.id, work.id, english.id)

      assert %{expression: answered} = Selection.for_principal(work.id, principal.id, profile)
      assert answered.id == english.id
    end

    test "an expression that does not realize the work is refused", %{principal: principal} do
      %{work: work} = a_film_in_two_languages()
      {:ok, %{expression: elsewhere}} = Catalog.create_work("Another film")

      assert {:error, changeset} = Selection.choose(principal.id, work.id, elsewhere.id)
      assert "does not realize that work" in errors_on(changeset).expression_id
    end

    test "one principal's choice does not reach another", %{principal: principal} do
      %{work: work, russian: russian} = a_film_in_two_languages()
      {:ok, other} = Principals.create_principal(%{role: "member"})

      {:ok, _chosen} = Selection.choose(principal.id, work.id, russian.id)

      assert Selection.chosen(principal.id, work.id) == russian.id
      assert Selection.chosen(other.id, work.id) == nil
    end
  end

  describe "what the principal prefers comes next" do
    test "the audio language range picks the expression named in it", %{
      principal: principal,
      profile: profile
    } do
      %{work: work, english: english} = a_film_in_two_languages()
      {:ok, _set} = Preferences.set(principal.id, "audio_language", "en")

      assert %{expression: answered, by: :preferred} =
               Selection.for_principal(work.id, principal.id, profile)

      assert answered.id == english.id
    end

    test "a range nothing matches falls through to what the work is", %{
      principal: principal,
      profile: profile
    } do
      # §8.6 forbids reporting an absence: a preference nothing satisfies is not an error.
      %{work: work} = a_film_in_two_languages()
      {:ok, _set} = Preferences.set(principal.id, "audio_language", "ja")

      assert %{expression: answered, by: :nearest} =
               Selection.for_principal(work.id, principal.id, profile)

      refute answered == nil
    end

    test "stating no language leaves the work to decide", %{
      principal: principal,
      profile: profile
    } do
      %{work: work, russian: russian} = a_film_in_two_languages()

      # The default range narrows nothing, so the answer is the nearest by identifier, which
      # is the expression placement made first.
      assert %{expression: answered} = Selection.for_principal(work.id, principal.id, profile)
      assert answered.id == russian.id
    end
  end

  describe "what the work is decides the rest" do
    test "the expression nearest the canonical form answers", %{
      principal: principal,
      profile: profile
    } do
      %{work: work, russian: russian, english: english} = a_film_in_two_languages()

      {:ok, _canonical} = Representative.represent(work.id, %{"aspect_ratio" => 1.33})
      {:ok, _described} = Representative.describe(english.id, %{"aspect_ratio" => 1.33})
      {:ok, _differs} = Representative.describe(russian.id, %{"aspect_ratio" => 2.35})

      assert %{expression: answered, by: :nearest} =
               Selection.for_principal(work.id, principal.id, profile)

      assert answered.id == english.id
    end

    test "the same work answers alike across calls", %{principal: principal, profile: profile} do
      %{work: work} = a_film_in_two_languages()

      first = Selection.for_principal(work.id, principal.id, profile)

      assert Selection.for_principal(work.id, principal.id, profile) == first
    end
  end
end
