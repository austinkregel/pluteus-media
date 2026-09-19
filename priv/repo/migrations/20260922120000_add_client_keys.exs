defmodule Pluteus.Repo.Migrations.AddClientKeys do
  use Ecto.Migration

  # spec-07 §3.2. A client key is a device's credential, held only as a digest.
  # A device bound some other way, such as the device authorization grant, has
  # none.
  def change do
    alter table(:devices) do
      add :key_digest, :text
    end

    create unique_index(:devices, [:key_digest], where: "key_digest IS NOT NULL")
  end
end
