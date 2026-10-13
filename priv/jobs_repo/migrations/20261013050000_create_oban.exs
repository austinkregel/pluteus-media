defmodule Pluteus.Jobs.Repo.Migrations.CreateOban do
  use Ecto.Migration

  # Pinned, so that upgrading Oban changes nothing this migration does. A later
  # schema version arrives as a migration of its own.
  def up, do: Oban.Migrations.up(version: 14)

  def down, do: Oban.Migrations.down(version: 1)
end
