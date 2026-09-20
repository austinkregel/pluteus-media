defmodule Pluteus.Repo.Migrations.NumberDevicesForPlayers do
  use Ecto.Migration

  # [OPENSUBSONIC] types a player's identifier as an integer, and a device is
  # what plays here (spec-07 §3.3). The number is the device's on that surface;
  # nothing else reads it, and the device's own identifier stays what it is.

  def change do
    alter table(:devices) do
      add :player_number, :bigserial, null: false
    end

    create unique_index(:devices, [:player_number])
  end
end
