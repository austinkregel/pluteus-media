defmodule Pluteus.Repo.Migrations.RecordWhatAQueueEntryWasQueuedFrom do
  @moduledoc """
  [spec-10] §12.3 requires that "each entry MUST record what it was queued from, so that
  'clear the rest of this release' is answerable without guessing". The table held a res
  and a position and nothing else, so the question could only be answered by inferring
  the grouping back from the res — and a track reached from a release, from a household
  sequence and on its own are three different answers that the res alone cannot tell
  apart.

  Nullable, because an entry queued on its own was queued from nothing. That is the
  stated case rather than an unrecorded one: §12.3 asks what it was queued from, and for
  such an entry there is no such thing.
  """

  use Ecto.Migration

  def change do
    alter table(:play_queue_entries) do
      add :queued_from, references(:res, type: :uuid, on_delete: :nothing)
    end

    create index(:play_queue_entries, [:queued_from])
  end
end
