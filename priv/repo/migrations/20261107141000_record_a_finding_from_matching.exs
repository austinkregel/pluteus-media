defmodule Pluteus.Repo.Migrations.RecordAFindingFromMatching do
  use Ecto.Migration

  # spec-05 §12: a matching stage that cannot complete records why as a finding a person
  # can see, against the holding it could not complete for.
  @stages ~w(acquire examine identify place normalize analyse purge credit corpus)

  def up, do: replace_stages(@stages ++ ["match"])

  def down, do: replace_stages(@stages)

  defp replace_stages(stages) do
    drop constraint(:ingest_findings, :stage_must_be_known)

    create constraint(:ingest_findings, :stage_must_be_known,
             check: "stage IN (#{Enum.map_join(stages, ", ", &"'#{&1}'")})"
           )
  end
end
