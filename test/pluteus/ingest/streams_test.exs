defmodule Pluteus.Ingest.StreamsTest do
  @moduledoc """
  Reading a date out of a container's own tags.

  The reading is pure, so it is exercised directly rather than through a placed file:
  what matters is which values are a date and which are not, and a file carrying each
  would say the same thing more slowly.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Ingest.Registry
  alias Pluteus.Ingest.Streams

  describe "spec-01 §6.4. The date a container states, at the precision it states it" do
    test "a year is a year" do
      assert date(%{"date" => "2019"}) == "2019"
    end

    test "a year and a month keep the month" do
      assert date(%{"date" => "2019-05"}) == "2019-05"
    end

    test "a day keeps the day" do
      assert date(%{"date" => "2019-05-04"}) == "2019-05-04"
    end

    test "a year is not completed to January, because the file did not say January" do
      # The precision is itself evidence. A surface showing "1 January 2019" for a file
      # stating 2019 would be showing something nothing established.
      refute date(%{"date" => "2019"}) == "2019-01-01"
      refute date(%{"date" => "2019-05"}) == "2019-05-01"
    end

    test "a time of day is read to the day" do
      # A tagger may write a full timestamp where the format permits one. What is being
      # dated is an edition, which is not issued at a time of day.
      assert date(%{"date" => "2019-05-04T13:45:00Z"}) == "2019-05-04"
      assert date(%{"date" => "2019-05-04 13:45:00"}) == "2019-05-04"
    end

    test "the tags are read in the registry's order, most specific first" do
      assert date(%{"date" => "2019-05-04", "year" => "1999"}) == "2019-05-04"
      assert date(%{"premiered" => "2019-05-04", "year" => "1999"}) == "2019-05-04"
      assert date(%{"year" => "1999"}) == "1999"
    end

    test "a date whose field order its own form does not fix gives no date" do
      # 04/05/2019 is the fourth of May, the fifth of April, or neither, and the form
      # says which only by a convention the file does not carry. The three readings are
      # a month and a year apart, so none of them is preferred here.
      assert date(%{"date" => "04/05/2019"}) == nil
      assert date(%{"date" => "2019/05/04"}) == nil
      assert date(%{"date" => "4 May 2019"}) == nil
    end

    test "a day no calendar has gives no date" do
      assert date(%{"date" => "2019-02-30"}) == nil
      assert date(%{"date" => "2019-13-01"}) == nil
    end

    test "a month no year has gives no date" do
      assert date(%{"date" => "2019-13"}) == nil
      assert date(%{"date" => "2019-00"}) == nil
    end

    test "something that is not a number gives no date" do
      assert date(%{"date" => "unknown"}) == nil
      assert date(%{"date" => "20xx"}) == nil
      assert date(%{"date" => ""}) == nil
    end

    test "surrounding space does not stop a date being read" do
      assert date(%{"date" => "  2019-05-04 "}) == "2019-05-04"
    end

    test "a container stating none states none" do
      assert date(%{}) == nil
      assert date(%{"album" => "Kind of Blue"}) == nil
    end
  end

  defp date(tags), do: Streams.date(tags, Registry.issued_by())
end
