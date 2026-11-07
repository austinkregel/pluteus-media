defmodule Pluteus.Repo.Migrations.RaiseACandidateFromMatching do
  use Ecto.Migration

  # spec-05 §8.5: everything resting on a resemblance is raised as a candidate through
  # spec-03 §8.3's mechanism — a pair, a proposed decision, the source, the evidence, and
  # the source's own score where it gave one — and a candidate matching raised and one a
  # member proposed appear in one place.
  #
  # A candidate from matching proposes what deciding it would write, names its source,
  # and points at the match record holding the evidence. Accepting a place of capture is
  # deciding the pair as the proposal says; rejecting it is deciding it distinct.
  @signals ~w(digest perceptual external_identifier member)
  @decisions ~w(same_holding same_manifestation same_expression same_work distinct)

  def up do
    alter table(:duplicate_candidates) do
      add :proposed, :text
      add :source, :text
      add :match_record_id, references(:match_records, type: :uuid, on_delete: :nothing)
      add :score, :float
    end

    replace(:signal_must_be_known, "signal", @signals ++ ["matching"])
    replace(:decision_must_be_known, "decision", @decisions ++ ["place_of_capture"], nullable: true)

    create constraint(:duplicate_candidates, :a_matching_candidate_names_its_evidence,
             check:
               "(signal = 'matching') = " <>
                 "(proposed IS NOT NULL AND source IS NOT NULL AND match_record_id IS NOT NULL)"
           )

    # A proposal is decided as proposed or as distinct, and nothing else; a pair nothing
    # proposed is decided at a level of sameness.
    create constraint(:duplicate_candidates, :a_proposal_is_decided_as_proposed,
             check:
               "decision IS NULL " <>
                 "OR decision = 'distinct' " <>
                 "OR (proposed IS NULL AND decision <> 'place_of_capture') " <>
                 "OR (proposed IS NOT NULL AND decision = proposed)"
           )
  end

  def down do
    drop constraint(:duplicate_candidates, :a_proposal_is_decided_as_proposed)
    drop constraint(:duplicate_candidates, :a_matching_candidate_names_its_evidence)

    replace(:decision_must_be_known, "decision", @decisions, nullable: true)
    replace(:signal_must_be_known, "signal", @signals)

    alter table(:duplicate_candidates) do
      remove :score
      remove :match_record_id
      remove :source
      remove :proposed
    end
  end

  defp replace(name, column, values, options \\ []) do
    drop constraint(:duplicate_candidates, name)

    known = "#{column} IN (#{Enum.map_join(values, ", ", &"'#{&1}'")})"
    check = if options[:nullable], do: "#{column} IS NULL OR #{known}", else: known

    create constraint(:duplicate_candidates, name, check: check)
  end
end
