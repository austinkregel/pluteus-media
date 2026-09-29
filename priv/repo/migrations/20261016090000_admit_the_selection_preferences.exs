defmodule Pluteus.Repo.Migrations.AdmitTheSelectionPreferences do
  use Ecto.Migration

  # spec-01 §8.6's three independent settings. It forbids collapsing them into a single
  # language preference, so they are three keys and not one, and none of them is the
  # `language` key the resolution profile reads: §8.6 makes naming and selection orthogonal
  # axes, and a household name in one language with personal audio in another is coherent.
  @selection ~w(audio_language subtitle_language subtitle_visibility)

  @keys ~w(
    theme contrast motion density text_size described_audio automatic_preview
    next_member_offer
    language
    caption_face caption_size caption_ground caption_edge
    reading_face reading_size reading_line_height reading_measure
    reading_letter_spacing reading_word_spacing
    reading_alignment reading_hyphenation reading_theme
    browse_continue browse_recently_added browse_people browse_places browse_time
    browse_sets browse_everything
  )

  def up do
    replace_key_check(@keys ++ @selection)
  end

  def down do
    execute(
      "DELETE FROM principal_preferences WHERE key = ANY (ARRAY[#{quoted(@selection)}]::text[])"
    )

    replace_key_check(@keys)
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
