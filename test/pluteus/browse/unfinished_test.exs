defmodule Pluteus.Browse.UnfinishedTest do
  @moduledoc """
  The gateway's four doors into unfinished work (spec-10 §9.2, §14.3).

  Criterion 34 and §14.3 are what most of this is about: one of the four doors is about
  looking, and looking is consumption. The band is the place a household total would be
  easiest to put and hardest to notice.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Browse.Unfinished
  alias Pluteus.Catalog
  alias Pluteus.Consumption
  alias Pluteus.Dedup
  alias Pluteus.Ingest.Place
  alias Pluteus.PrincipalFixtures
  alias Pluteus.Principals

  setup do
    %{ada: member("ada"), bob: member("bob")}
  end

  describe "§14.3. The door about looking reports no figure" do
    test "it carries no count, whatever the catalogue holds", %{ada: ada} do
      for _each <- 1..4, do: work()

      assert %{count: nil} = door(ada, "nothing_you_have_looked_at")
    end

    test "it is open where this principal has looked at nothing", %{ada: ada} do
      work()

      assert %{any?: true} = door(ada, "nothing_you_have_looked_at")
    end

    test "it closes once this principal has looked at everything", %{ada: ada} do
      looked_at(ada, work())

      assert %{any?: false} = door(ada, "nothing_you_have_looked_at")
    end

    test "another principal's looking does not close it", %{ada: ada, bob: bob} do
      # The criterion itself: composing this from both principals' consumption would
      # close Ada's door because Bob looked, which tells Ada what Bob did.
      looked_at(bob, work())

      assert %{any?: true} = door(ada, "nothing_you_have_looked_at")
    end

    test "one principal's looking does not open or close another's", %{ada: ada, bob: bob} do
      held = work()
      looked_at(ada, held)

      assert %{any?: false} = door(ada, "nothing_you_have_looked_at")
      assert %{any?: true} = door(bob, "nothing_you_have_looked_at")
    end
  end

  describe "§9.2. The other three doors count what the catalogue and its derivations say" do
    test "a holding whose container stated no date is behind the date door", %{ada: ada} do
      work()

      assert %{count: 1, any?: true} = door(ada, "no_date_recorded")
    end

    test "a dated holding is not", %{ada: ada} do
      dated(work())

      assert %{count: 0, any?: false} = door(ada, "no_date_recorded")
    end

    test "an open candidate needs a decision and a settled one does not", %{ada: ada} do
      left = work()
      right = work()

      {:ok, candidate} = Dedup.propose(left, right, ada.id)

      assert %{count: 1, any?: true} = door(ada, "needs_a_decision")

      {:ok, _} = Dedup.decide(candidate.id, :distinct, ada.id)

      assert %{count: 0, any?: false} = door(ada, "needs_a_decision")
    end

    test "every door is answered, and only the one about looking withholds its figure",
         %{ada: ada} do
      doors = Unfinished.for_principal(ada.id)

      assert [_looking, _unverified, _undated, _undecided] = doors

      for door <- doors do
        if door.bucket == "nothing_you_have_looked_at",
          do: assert(door.count == nil),
          else: assert(is_integer(door.count))
      end
    end
  end

  defp door(principal, bucket) do
    Enum.find(Unfinished.for_principal(principal.id), &(&1.bucket == bucket))
  end

  # A consumption event names the device it happened on, and the composite foreign key
  # requires that device be the principal's own, so each member here has one.
  defp member(label) do
    {:ok, principal} = Principals.create_principal(%{role: "member"})
    device = PrincipalFixtures.a_device(principal.id, label)

    %{id: principal.id, device_id: device.id}
  end

  defp work do
    {:ok, %{work: work}} =
      Catalog.create_work(%{nomen_string: "a holding", provenance: :automatic})

    {:ok, _} = Catalog.categorize(work.id, Place.category_scheme(), "photograph", :automatic)

    work.id
  end

  defp dated(work_id) do
    [expression] = Catalog.expressions_of(work_id)
    [manifestation] = Catalog.manifestations_of(expression.id)

    {:ok, %{res: span}} =
      Catalog.create_named_res(:time_span, %{nomen_string: "1959", provenance: :automatic})

    {:ok, _} =
      Catalog.associate(manifestation.id, span.id, "time-of-publication-or-manufacture")

    work_id
  end

  defp looked_at(principal, work_id) do
    {:ok, _} = Consumption.played(principal.id, principal.device_id, work_id)

    work_id
  end
end
