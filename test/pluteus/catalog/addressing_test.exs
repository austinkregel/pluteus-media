defmodule Pluteus.Catalog.AddressingTest do
  @moduledoc """
  Addressing behaviour spec-01 §8 and §9 require that §15 does not enumerate.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Catalog.DeepLink

  describe "§8.5, a page is addressed at manifestation and below" do
    test "page forty-two of a scanned edition is accepted" do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("Middlemarch")

      assert {:ok, %{address: address}} =
               Catalog.create_address(manifestation.id, %{selector_type: :page, page_number: 42})

      assert address.target_kind == :manifestation
    end

    test "a page of the expression is refused, since another edition repaginates" do
      {:ok, %{expression: expression}} = Catalog.create_work("Middlemarch")

      assert {:error, :address, changeset, _changes} =
               Catalog.create_address(expression.id, %{selector_type: :page, page_number: 42})

      assert %{target_kind: [_ | _]} = errors_on(changeset)

      assert {:error, {:selector_invalid_at_level, :page, :expression}} =
               DeepLink.parse("/expressions/#{expression.id}?page=42")
    end
  end

  describe "§9.1, a link carries one selector of one type" do
    test "a page and a character range together name no selector type" do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("Middlemarch")

      assert {:error, {:no_selector_type_for, ["char", "page"]}} =
               DeepLink.parse("/manifestations/#{manifestation.id}?page=42&char=1200,1340")
    end

    test "a time range and a region together are the one spatiotemporal selector" do
      {:ok, %{manifestation: manifestation}} = Catalog.create_work("The Dig")

      assert {:ok, %{selector_type: :spatiotemporal}} =
               DeepLink.parse(
                 "/manifestations/#{manifestation.id}?t=140,148&xywh=percent:25,25,50,50"
               )
    end
  end
end
