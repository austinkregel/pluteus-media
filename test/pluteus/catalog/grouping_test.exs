defmodule Pluteus.Catalog.GroupingTest do
  @moduledoc """
  A res carrying ordered members, and the order it carries them in ([spec-10] §8.3).

  §8.3 gives two relations that may carry an order and forbids presenting one's positions
  as the other's, so what is asserted here is that exactly one answers for each shape,
  and that the order is the one that relation holds.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Grouping

  describe "§8.3. A release and its tracks are ordered by the whole-part positions" do
    test "the members are the tracks, in position order, and not the media" do
      # A person asking for a release means its tracks. The disc is how they are
      # grouped, and the walk is two levels rather than one.
      %{release: release, tracks: tracks} = a_release(["So What", "Freddie", "Blue"])

      assert Grouping.members_of(release) == tracks
    end

    test "a track names the release as the grouping it is a member of" do
      %{release: release, tracks: [_first, second, _third]} = a_release(["A", "B", "C"])

      assert Grouping.grouping_of(second) == release
    end

    test "a track carries no members of its own" do
      %{tracks: [first | _rest]} = a_release(["A", "B"])

      assert Grouping.members_of(first) == []
    end

    test "the order follows the positions rather than the order of creation" do
      # Written out of order on purpose: a query returning rows in insertion order would
      # pass a test that built them in the order it expected.
      %{release: release, tracks: [a, b, c]} = a_release(["A", "B", "C"], positions: [3, 1, 2])

      assert Grouping.members_of(release) == [b, c, a]
    end
  end

  describe "§8.3. An aggregate with no part structure is ordered by the arrangement" do
    test "the members come back in the arrangement's order" do
      %{sequence: sequence, members: [a, b, c]} = a_sequence(["One", "Two", "Three"], [3, 1, 2])

      assert Grouping.members_of(sequence) == [b, c, a]
    end

    test "a member names the sequence it is a member of" do
      %{sequence: sequence, members: [a | _rest]} = a_sequence(["One", "Two"], [1, 2])

      assert Grouping.grouping_of(a) == sequence
    end
  end

  describe "A holding that is neither a grouping nor a member" do
    test "carries no members and is a member of nothing" do
      {:ok, %{work: work}} = Catalog.create_work("Harbour at dawn")

      assert Grouping.members_of(work.id) == []
      assert Grouping.grouping_of(work.id) == nil
    end
  end

  # A release as placement makes one: the release work's expression aggregates each
  # track's, and each track's manifestation is a part of a medium that is a part of the
  # release's own manifestation.
  defp a_release(titles, opts \\ []) do
    positions = Keyword.get(opts, :positions, Enum.to_list(1..length(titles)))

    {:ok, %{work: work, expression: expression, manifestation: manifestation}} =
      Catalog.create_work("Kind of Blue")

    {:ok, %{manifestation: medium}} = Catalog.add_manifestation(expression.id, "disc 1")
    {:ok, _} = Catalog.add_manifestation_part(manifestation.id, medium.id, 1)

    tracks =
      for {title, position} <- Enum.zip(titles, positions) do
        {:ok, %{work: track, expression: recording, manifestation: side}} =
          Catalog.create_work(title)

        {:ok, _} = Catalog.add_manifestation_part(medium.id, side.id, position)
        {:ok, _} = Catalog.aggregate(expression.id, recording.id)

        track.id
      end

    %{release: work.id, tracks: tracks}
  end

  # spec-01 §12.1's aggregate "with no such structure, such as a sequence the household
  # composes": nothing is a part of anything, and the aggregation carries the order.
  defp a_sequence(titles, arrangements) do
    {:ok, %{work: work, expression: expression}} = Catalog.create_work("An evening")

    members =
      for {title, arrangement} <- Enum.zip(titles, arrangements) do
        {:ok, %{work: member, expression: realized}} = Catalog.create_work(title)

        {:ok, _} = Catalog.aggregate(expression.id, realized.id)
        1 = Catalog.arrange(expression.id, realized.id, arrangement)

        member.id
      end

    %{sequence: work.id, members: members}
  end
end
