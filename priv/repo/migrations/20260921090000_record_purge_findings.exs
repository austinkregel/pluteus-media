defmodule Pluteus.Repo.Migrations.RecordPurgeFindings do
  use Ecto.Migration

  # spec-01 §14.3. A purge commits the catalog before removing bytes, so bytes
  # it could not remove outlive their record. They are a finding against their
  # location, which outlives the job that failed to remove them.
  @stages ~w(acquire identify place normalize analyse purge)
  @prior_stages ~w(acquire identify place normalize analyse)

  def up, do: replace_stages(@stages)
  def down, do: replace_stages(@prior_stages)

  defp replace_stages(stages) do
    drop constraint(:ingest_findings, :stage_must_be_known)

    create constraint(:ingest_findings, :stage_must_be_known,
             check: "stage IN (#{Enum.map_join(stages, ", ", &"'#{&1}'")})"
           )
  end
end
