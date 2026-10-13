defmodule Pluteus.Repo.Migrations.TakeTheQueueOutOfTheCatalogue do
  use Ecto.Migration

  # The queue now has a database of its own, so its tables leave this one. Written as a
  # migration forward rather than as a rollback of the one that created them: that
  # migration ran, and saying it did not would make the history a different story from
  # what happened.
  #
  # Dropping these loses whatever was queued, which costs nothing. spec-04 §3 makes every
  # stage scheduled work that finds its own due items from recorded state, and criterion
  # 27 asserts it — emptying the queue is a thing the suite does on purpose.
  def up, do: Oban.Migrations.down(version: 1)

  def down, do: Oban.Migrations.up(version: 14)
end
