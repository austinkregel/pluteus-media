defmodule Pluteus.Repo.Migrations.AdmitAPackageAndSoftware do
  use Ecto.Migration

  # spec-04 §6.9. A comic archive is a package and a cartridge or disc dump is
  # software, so identification answers seven broad classes.
  @widened ~w(companion audio video image text package software)
  @narrowed ~w(companion audio video image text)

  def up do
    drop constraint(:acquisitions, :media_class_must_be_known)

    create constraint(:acquisitions, :media_class_must_be_known,
             check: "media_class IS NULL OR #{in_list("media_class", @widened)}"
           )
  end

  def down do
    drop constraint(:acquisitions, :media_class_must_be_known)

    create constraint(:acquisitions, :media_class_must_be_known,
             check: "media_class IS NULL OR #{in_list("media_class", @narrowed)}"
           )
  end

  defp in_list(column, values) do
    "#{column} IN (#{Enum.map_join(values, ", ", &"'#{&1}'")})"
  end
end
