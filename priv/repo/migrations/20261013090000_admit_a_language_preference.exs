defmodule Pluteus.Repo.Migrations.AdmitALanguagePreference do
  use Ecto.Migration

  # spec-01 §7.4's resolution profile is per principal and persists, and the language
  # range it carries is the part of it a person chooses. The assigner is not held: §7.4
  # takes it from the principal's own person. Neither is the calendar, which resolves
  # among a time-span's nomens and so needs the nomen schemes [spec-10] §20 names and
  # nothing has seeded.
  @keys ~w(
    theme contrast motion density text_size described_audio automatic_preview
    next_member_offer
    language
    caption_face caption_size caption_ground caption_edge
    browse_continue browse_recently_added browse_people browse_places browse_time
    browse_sets browse_everything
  )

  @without_language List.delete(@keys, "language")

  def up do
    replace_key_check(@keys)
  end

  def down do
    execute("DELETE FROM principal_preferences WHERE key = 'language'")

    replace_key_check(@without_language)
  end

  defp replace_key_check(keys) do
    drop(constraint(:principal_preferences, :preference_key_is_known))

    create(
      constraint(:principal_preferences, :preference_key_is_known,
        check: "key = ANY (ARRAY[#{quoted(keys)}]::text[])"
      )
    )
  end

  defp quoted(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
