defmodule Pluteus.Repo.Migrations.DecideTwoThingsAreOneManifestation do
  use Ecto.Migration

  # spec-03 §8.3. *same manifestation* is the level between *same holding* and
  # *same expression*: two manifestation rows standing for one manifestation,
  # whose digital items and items come under one of them. Two pressings of one
  # record are the same expression and two manifestations; two catalogue entries
  # for one pressing are this.
  @decisions ~w(same_holding same_manifestation same_expression same_work distinct)
  @narrowed ~w(same_holding same_expression same_work distinct)

  def up, do: replace_check(@decisions)

  def down, do: replace_check(@narrowed)

  defp replace_check(decisions) do
    drop constraint(:duplicate_candidates, :decision_must_be_known)

    create constraint(:duplicate_candidates, :decision_must_be_known,
             check: "decision IS NULL OR decision IN (#{in_list(decisions)})"
           )
  end

  defp in_list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
