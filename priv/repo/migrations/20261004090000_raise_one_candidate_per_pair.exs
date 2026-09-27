defmodule Pluteus.Repo.Migrations.RaiseOneCandidatePerPair do
  use Ecto.Migration

  # spec-03 §8.3 and [spec-05] §8.5. A candidate matching raised and a candidate
  # a member proposed "are one kind of thing and appear in one place", and a
  # decided pair "is settled" whatever raised it. Keyed by pair and signal, a
  # pair decided under one signal was raised again as a new row under the next,
  # so the key is the pair and `signal` is the signal that first raised it.
  #
  # The database is what enforces it, rather than a check in each of detection,
  # a member's proposal and the matching that spec-05 has yet to introduce. The
  # rule holds for code not written yet.
  def up do
    # Where a pair holds several rows, the decided one stands and then the
    # earliest detected. `down` cannot restore what this removes, and where one
    # pair holds two different decisions one of them is lost, so a deployment
    # reads the pairs out before migrating.
    execute """
    DELETE FROM duplicate_candidates WHERE id IN (
      SELECT id FROM (
        SELECT id, row_number() OVER (
          PARTITION BY left_id, right_id
          ORDER BY (decision IS NOT NULL) DESC, detected_at, id
        ) AS standing
        FROM duplicate_candidates
      ) ranked WHERE ranked.standing > 1
    )
    """

    drop unique_index(:duplicate_candidates, [:left_id, :right_id, :signal])
    create unique_index(:duplicate_candidates, [:left_id, :right_id])
  end

  def down do
    drop unique_index(:duplicate_candidates, [:left_id, :right_id])
    create unique_index(:duplicate_candidates, [:left_id, :right_id, :signal])
  end
end
