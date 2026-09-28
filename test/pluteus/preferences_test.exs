defmodule Pluteus.PreferencesTest do
  @moduledoc """
  spec-10 §14.5 and §21: a principal's presentation preferences are that principal's,
  are not household-visible, and disclose a disability as a play history discloses a
  taste.

  What is asserted here is that the store keeps that guarantee by its shape rather
  than by a check — there is no function taking one principal and answering another's
  — and that §20's rule holds: a value the registry omits cannot reach a row.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Preferences
  alias Pluteus.Preferences.Registry
  alias Pluteus.Principals

  setup do
    {:ok, other} = Principals.create_principal(%{role: "member"})

    %{other: other}
  end

  describe "spec-10 §20. No value a registry omits" do
    test "every key the registry names has a domain and a default inside it" do
      for key <- Registry.keys() do
        assert %{"kind" => kind} = Registry.domain(key)
        assert kind in ~w(one_of number)

        assert Registry.admits?(key, Registry.default(key)),
               "#{key}'s default is outside its own domain"
      end
    end

    test "the database's key check and the registry agree" do
      # The check is what a caller cannot forget; the registry is what a caller reads.
      # Either drifting would let a key exist that nothing can validate, or refuse one
      # the registry offers.
      %{rows: [[definition]]} =
        Repo.query!(
          "SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = $1",
          ["preference_key_is_known"]
        )

      for key <- Registry.keys() do
        assert definition =~ "'#{key}'", "#{key} is in the registry and not in the check"
      end

      quoted = Regex.scan(~r/'([a-z_]+)'/, definition, capture: :all_but_first)

      assert quoted |> List.flatten() |> Enum.sort() == Registry.keys()
    end

    test "§9.2's seven modes are each hideable, and nothing else is" do
      # §9.2 fixes the modes, so the key set is closed and a mode without a key would
      # be one a principal cannot hide. Continue is among them deliberately: the
      # section calls it "the most-used entry point in a household media system", and
      # a person may still not want it.
      modes = ~w(continue recently_added people places time sets everything)

      for mode <- modes do
        assert "browse_#{mode}" in Registry.keys()
        assert Registry.default("browse_#{mode}") == "shown"
        assert Registry.admits?("browse_#{mode}", "hidden")
      end

      hideable = Enum.filter(Registry.keys(), &String.starts_with?(&1, "browse_"))

      assert length(hideable) == length(modes)
    end

    test "caption presentation is adjustable in every property the deployment draws" do
      # §17.4 requires it "be adjustable by the person, persisted per principal" and
      # names no property, so these four are the deployment's own seed data. The ground
      # is the one that carries the contrast: a caption sits over moving picture, so no
      # floor is meetable by the ink alone.
      for property <- ~w(caption_face caption_size caption_ground caption_edge) do
        assert property in Registry.keys()
      end

      assert Registry.admits?("caption_ground", "none")
      assert Registry.admits?("caption_edge", "outline")
      refute Registry.admits?("caption_ground", "transparent")
    end

    test "a key outside the registry is refused", %{actor: actor} do
      assert {:error, changeset} = Preferences.set(actor.id, "favourite_colour", "blue")
      assert "is invalid" in errors_on(changeset).key
    end

    test "a value outside its key's domain is refused", %{actor: actor} do
      assert {:error, changeset} = Preferences.set(actor.id, "motion", "sideways")
      assert ["is outside motion's domain"] = errors_on(changeset).value
    end

    test "a number outside its bounds is refused, and one inside is taken", %{actor: actor} do
      assert {:error, _changeset} = Preferences.set(actor.id, "text_size", "99")
      assert {:error, _changeset} = Preferences.set(actor.id, "text_size", "201")
      assert {:error, _changeset} = Preferences.set(actor.id, "text_size", "large")
      assert {:ok, _preference} = Preferences.set(actor.id, "text_size", "150")
    end
  end

  describe "spec-10 §14.5. A principal's own, and no other's" do
    test "one principal's preference does not reach another", %{actor: actor, other: other} do
      {:ok, _set} = Preferences.set(actor.id, "motion", "reduced")

      assert Preferences.held(actor.id, "motion") == "reduced"
      assert Preferences.held(other.id, "motion") == Registry.default("motion")
      refute Preferences.held_by(other.id)["motion"] == "reduced"
    end

    test "nothing here reads across principals" do
      # The guarantee is the shape rather than a check inside a function: every public
      # function names the principal whose preferences it answers, so there is no call
      # that could return another's.
      arities = Preferences.__info__(:functions)

      assert Enum.sort(arities) == [
               forget: 2,
               held: 2,
               held_by: 1,
               set: 3,
               set_many: 2
             ]
    end

    test "a preference writes no change-feed entry", %{actor: actor} do
      # §14.5 puts these outside both classes: a preference is not a catalog write, and
      # the section says in terms that they "are not consumption data". So the table
      # carries neither trigger, and nothing is pushed to anybody.
      before = Repo.aggregate("catalog_writes", :count)

      {:ok, _set} = Preferences.set(actor.id, "contrast", "more")

      assert Repo.aggregate("catalog_writes", :count) == before
    end
  end

  describe "Defaults come from the registry, and an unset preference is an absent row" do
    test "a principal who has set nothing is answered every default", %{actor: actor} do
      assert Preferences.held_by(actor.id) == Registry.defaults()
      assert Repo.aggregate(Preferences.Preference, :count) == 0
    end

    test "setting replaces rather than accumulating", %{actor: actor} do
      {:ok, _first} = Preferences.set(actor.id, "theme", "light")
      {:ok, _second} = Preferences.set(actor.id, "theme", "dark")

      assert Preferences.held(actor.id, "theme") == "dark"
      assert Repo.aggregate(Preferences.Preference, :count) == 1
    end

    test "forgetting returns a preference to its default", %{actor: actor} do
      {:ok, _set} = Preferences.set(actor.id, "density", "compact")
      :ok = Preferences.forget(actor.id, "density")

      assert Preferences.held(actor.id, "density") == "comfortable"
      assert Repo.aggregate(Preferences.Preference, :count) == 0
    end
  end

  describe "A set is written whole or not at all" do
    test "several preferences land together", %{actor: actor} do
      assert {:ok, held} =
               Preferences.set_many(actor.id, %{"theme" => "light", "motion" => "reduced"})

      assert held["theme"] == "light"
      assert held["motion"] == "reduced"
    end

    test "one bad value leaves every other unwritten", %{actor: actor} do
      assert {:error, "motion", _changeset} =
               Preferences.set_many(actor.id, %{"theme" => "light", "motion" => "sideways"})

      assert Preferences.held(actor.id, "theme") == Registry.default("theme")
      assert Repo.aggregate(Preferences.Preference, :count) == 0
    end
  end
end
