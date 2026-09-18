defmodule Pluteus.Repo.Migrations.CreateDigitalItemsAndAssets do
  use Ecto.Migration

  # §5.5's four role classes are normative; the values inside them are seed data
  # (§17). Backup scope reads the class, not the value, so a role nobody has
  # named yet still lands on the right side of §13.7.
  @role_classes ~w(acquired normalized redundant derived)

  def change do
    # §5.2. Item is entirely physical; a file or package of files carrying a
    # manifestation's content is this instead. Substantially every holding here
    # is one.
    create table(:digital_items, primary_key: false) do
      add :id, references(:res, type: :uuid, on_delete: :nothing), primary_key: true

      add :manifestation_id, references(:manifestations, type: :uuid, on_delete: :nothing),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:digital_items, [:manifestation_id])

    # §5.5. A digital item states what the household holds; an asset records one
    # stored byte sequence realizing it somewhere. The column is scalar, so an
    # asset naming two digital items is not a shape the table admits.
    #
    # There is no constraint requiring a digital item to have any asset. Zero
    # denotes a holding whose copies are all lost, which §5.5 requires be
    # representable rather than rejected.
    create table(:assets, primary_key: false) do
      add :id, references(:res, type: :uuid, on_delete: :nothing), primary_key: true

      add :digital_item_id, references(:digital_items, type: :uuid, on_delete: :nothing),
        null: false

      add :role_class, :string, null: false
      add :role, :string, null: false
      add :location, :text, null: false

      # §12.1's preservation ordering, for a digital item realized by several
      # assets that are parts rather than alternatives — disc two of a rip.
      # Arrangement does not live here; it is a catalog fact and survives the
      # loss of every copy.
      add :part_sequence, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create index(:assets, [:digital_item_id])
    create index(:assets, [:role_class])

    create constraint(:assets, :role_class_must_be_known,
             check: "role_class IN (#{Enum.map_join(@role_classes, ", ", &"'#{&1}'")})"
           )

    # §12.1's arrangement: which position an aggregated expression takes in the
    # aggregate. Nullable, since a single-member aggregate orders nothing.
    alter table(:aggregations) do
      add :arrangement, :integer
    end
  end
end
