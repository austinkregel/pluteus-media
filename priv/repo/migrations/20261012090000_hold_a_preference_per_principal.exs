defmodule Pluteus.Repo.Migrations.HoldAPreferencePerPrincipal do
  use Ecto.Migration

  # A row per key rather than a column per preference: the keys are heterogeneous and
  # arrive in groups from four sections, and a column each would be a migration each.
  #
  # The key's domain is stated here as well as in the registry, because a check the
  # database holds is one no caller can forget; a test asserts the two agree. The
  # value's domain is not, and cannot be — it differs per key, so the registry is the
  # only place that can hold it.
  @keys ~w(
    theme contrast motion density text_size described_audio automatic_preview
    next_member_offer
  )

  def up do
    create table(:principal_preferences, primary_key: false) do
      add :principal_id, references(:principals, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :key, :text, primary_key: true
      add :value, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:principal_preferences, :preference_key_is_known,
             check: "key = ANY (ARRAY[#{quoted(@keys)}]::text[])"
           )

    # [spec-10] §14.5: a principal's presentation preferences "MUST NOT be visible to
    # another", and §21 states they "are not household-visible". Deleting the principal
    # takes them, which is why the reference cascades where the rest of this schema's
    # do nothing: a preference has no meaning apart from the person whose it is, and
    # leaving one behind would outlive the guarantee.
    #
    # No change-feed trigger. §14.5 says these "are not consumption data", so they are
    # not in the consumption list, and a preference is not a catalog write, so they are
    # not in the catalog one.
  end

  def down do
    drop table(:principal_preferences)
  end

  defp quoted(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
