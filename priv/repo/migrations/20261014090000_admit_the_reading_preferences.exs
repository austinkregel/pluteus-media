defmodule Pluteus.Repo.Migrations.AdmitTheReadingPreferences do
  use Ecto.Migration

  # [ANNEX-A] A.3.6: a reader "MUST be able to set, per principal and persisted, the face,
  # size, line height, measure, letter and word spacing, alignment, hyphenation and theme
  # of long-form text". Nine, one key each, so the set is closed in the database as §9.2's
  # modes are.
  #
  # A.3.6 supplies the default for three of them — line height 1.55, alignment start,
  # hyphenation off — and the token file's own description of the serif family supplies a
  # fourth. The registry says of each remaining bound that it is this deployment's.
  @reading ~w(
    reading_face reading_size reading_line_height reading_measure
    reading_letter_spacing reading_word_spacing
    reading_alignment reading_hyphenation reading_theme
  )

  @keys ~w(
    theme contrast motion density text_size described_audio automatic_preview
    next_member_offer
    language
    caption_face caption_size caption_ground caption_edge
    browse_continue browse_recently_added browse_people browse_places browse_time
    browse_sets browse_everything
  )

  def up do
    replace_key_check(@keys ++ @reading)
  end

  def down do
    execute(
      "DELETE FROM principal_preferences WHERE key = ANY (ARRAY[#{quoted(@reading)}]::text[])"
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
