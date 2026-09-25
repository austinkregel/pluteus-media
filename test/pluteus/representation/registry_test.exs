defmodule Pluteus.Representation.RegistryTest do
  @moduledoc """
  The field names an absence assertion may be about (spec-10 §20), which spec-02
  §6.5 requires be drawn from a registry and which spec-02 criterion 12 tests.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Catalog.Res
  alias Pluteus.Representation.Registry

  test "every field names the kinds it may be asserted about, and each is a real kind" do
    kinds = Enum.map(Res.kinds(), &to_string/1)

    for field <- Registry.absence_fields() do
      assert is_binary(field["name"])
      assert field["kinds"] != [], "#{field["name"]} may be asserted about nothing"
      assert is_binary(field["for"]), "#{field["name"]} does not say what it is for"

      for kind <- field["kinds"] do
        assert kind in kinds, "#{field["name"]} names #{kind}, which is no kind of res"
      end
    end
  end

  test "a field name identifies one field" do
    names = Enum.map(Registry.absence_fields(), & &1["name"])

    assert names == Enum.uniq(names)
  end

  describe "the vocabulary is closed" do
    test "a name in it is named" do
      assert Registry.named?("creators")
      assert Registry.named?("language")
      assert Registry.named?("loudness")
    end

    test "a name outside it is not, so nothing may be asserted about it" do
      refute Registry.named?("mood")
      refute Registry.named?("photographer")
      refute Registry.named?("")
    end

    test "asking which kinds an unnamed field applies to raises" do
      assert_raise KeyError, fn -> Registry.kinds_of("mood") end
    end
  end

  describe "a field is asserted about the kind that holds it" do
    test "creators is a work's, and not a manifestation's" do
      assert Registry.about?("creators", :work)
      refute Registry.about?("creators", :manifestation)
    end

    test "assets is a digital item's, and digital_items a manifestation's" do
      assert Registry.about?("assets", :digital_item)
      assert Registry.about?("digital_items", :manifestation)
      refute Registry.about?("assets", :manifestation)
    end

    test "a time-span may be asserted at every level that carries one" do
      assert Registry.about?("time_span", :work)
      assert Registry.about?("time_span", :expression)
      assert Registry.about?("time_span", :manifestation)
    end

    test "an unnamed field is about nothing, rather than about everything" do
      refute Registry.about?("mood", :work)
    end
  end

  describe "a derived field names where its value and its failure come from" do
    test "a manifestation's loudness carries its tool, body type and measurement" do
      assert [field] = Registry.derived_fields(:manifestation)

      assert field["name"] == "loudness"
      assert field["derived"]["tool"] == "pluteus-native"
      assert field["derived"]["body_type"] == "measurements"
      assert field["derived"]["key"] == "loudness_lufs"
    end

    test "a kind with no derived field has none" do
      assert Registry.derived_fields(:work) == []
      assert Registry.derived_fields(:nomen) == []
    end

    test "every derived descriptor is whole" do
      for field <- Registry.absence_fields(), derived = field["derived"] do
        assert is_binary(derived["tool"])
        assert is_binary(derived["body_type"])
        assert is_binary(derived["key"])
      end
    end
  end
end
