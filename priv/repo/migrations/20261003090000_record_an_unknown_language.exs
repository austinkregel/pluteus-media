defmodule Pluteus.Repo.Migrations.RecordAnUnknownLanguage do
  use Ecto.Migration

  # spec-01 §7.2. A nomen's language takes three values and an implementation
  # MUST distinguish all three: a language, absent, or unknown. Null is absent,
  # never unknown, so unknown needs a column of its own.
  #
  # Unknown is a fact about provenance rather than about display — it is the
  # state a name arrives in from a source that stated no language ([spec-05]
  # §8.1) — and resolution treats it as no language, which is why nothing here
  # indexes it.
  #
  # `false` is what §7.2 already says the existing rows mean: no code path sets
  # a nomen's language, so every one of them is null, and a null is absent.
  def change do
    alter table(:nomens) do
      add :language_unknown, :boolean, null: false, default: false
    end

    create constraint(:nomens, :an_unknown_language_is_not_also_stated,
             check: "language IS NULL OR NOT language_unknown"
           )
  end
end
