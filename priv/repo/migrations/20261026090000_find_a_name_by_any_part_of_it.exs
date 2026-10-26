defmodule Pluteus.Repo.Migrations.FindANameByAnyPartOfIt do
  use Ecto.Migration

  # [spec-10] §9.5's search matches a term anywhere in any nomen, which a b-tree cannot
  # answer: a pattern opening with a wildcard has no prefix to descend by, so every search
  # would read every name the catalogue holds. A trigram index answers containment, and
  # case-insensitively, which is the match the search makes.
  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    execute """
    CREATE INDEX nomens_nomen_string_trigrams ON nomens
    USING gin (nomen_string gin_trgm_ops)
    """
  end

  def down do
    execute "DROP INDEX nomens_nomen_string_trigrams"
    execute "DROP EXTENSION pg_trgm"
  end
end
