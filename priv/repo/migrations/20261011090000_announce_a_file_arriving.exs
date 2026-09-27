defmodule Pluteus.Repo.Migrations.AnnounceAFileArriving do
  use Ecto.Migration

  # spec-01 §11.1: "An event may record a person playing a track, a file arriving,
  # or an asset being verified." A file arriving is §11.3's `acquired`, and it
  # happens before anything is catalogued — there is no res to name, so a res-keyed
  # table cannot hold one and one of the six types the vocabulary must distinguish
  # was unrecordable.
  #
  # Recording it at placement instead would name the asset it became, which reads
  # as the same thing and is not: a file that never identifies is never placed, so
  # the arrival a household most needs to see is the one that would go unannounced.
  # The acquisition is the record of the arrival and has an identifier of its own.
  #
  # Exactly one subject, never both and never neither: an event is about something,
  # and which kind it is about is what the check makes legible.
  def change do
    alter table(:platform_events) do
      modify :res_id, :uuid, null: true, from: {:uuid, null: false}

      add :acquisition_id, references(:acquisitions, type: :uuid, on_delete: :nothing)
    end

    create index(:platform_events, [:acquisition_id])

    create constraint(:platform_events, :one_subject,
             check: "num_nonnulls(res_id, acquisition_id) = 1"
           )
  end
end
