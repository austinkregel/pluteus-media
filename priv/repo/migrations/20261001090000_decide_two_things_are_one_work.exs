defmodule Pluteus.Repo.Migrations.DecideTwoThingsAreOneWork do
  use Ecto.Migration

  # spec-03 §8.3. The decision names the level it is about, and *same work* is the
  # level at which two realizations of one creation meet: a live recording and a
  # studio recording of one song, or two dumps of one game (spec-04 §6.9).
  @decisions ~w(same_holding same_expression same_work distinct)
  @narrowed ~w(same_holding same_expression distinct)

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
