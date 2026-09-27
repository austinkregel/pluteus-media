defmodule Pluteus.Repo.Migrations.HoldACredentialPerPrincipal do
  use Ecto.Migration

  # spec-06 §4.1: "A device MAY hold a credential for more than one principal,
  # each separately revocable. Revoking one leaves the others, and no credential
  # is reachable by the principal of another." A device row was itself the
  # credential — one `principal_id`, one `key_digest`, one `revoked_at` — so a
  # second principal on one screen meant a second device with its own identifier
  # and its own player number, and nothing said the two were one device. There was
  # no subject for the criterion to be about, and [spec-10] criterion 55's "per
  # principal per device" had nothing to be the same device.
  #
  # So `devices` becomes the physical thing that plays, holding what belongs to it
  # — its label and its player number (spec-07 §3.3) — and the credential becomes
  # a row of its own, keyed by the pair.
  #
  # The four tables that reference a device do so through a composite key carrying
  # the principal, which is what enforces "the device is always the principal's
  # own". Re-pointed at `device_credentials(device_id, principal_id)` that
  # invariant is preserved exactly, now reading as "a principal holds a credential
  # on that device" — and no column is renamed and no row reshaped in any of them.
  #
  # §4.2: "A credential MAY grant less than its principal may do. Its grant is
  # recorded with it and is a subset of the principal's role (§6.1); it MUST NOT be
  # widened by the principal's role changing afterwards." The grant belongs to the
  # credential, so it arrives here.
  @referring [
    {"events", "device_id"},
    {"now_playing", "device_id"},
    {"play_queues", "changed_by_device_id"},
    {"resume_positions", "device_id"}
  ]

  # spec-07 §3.4 and spec-10 §18.3 state one grant, in the same words in both:
  # reading the catalog, streaming, and writing its own principal's consumption.
  # Because administration and identity mapping are not in this set, §4.2's "MUST
  # NOT grant any operation in §6.1's Administrator row" is the column's domain
  # rather than a check somebody has to remember.
  @grantable ~w(read_catalog stream own_consumption)

  def up do
    create table(:device_credentials, primary_key: false) do
      add :device_id, references(:devices, type: :uuid, on_delete: :nothing), primary_key: true

      add :principal_id, references(:principals, type: :uuid, on_delete: :nothing),
        primary_key: true

      add :key_digest, :text
      add :granted, {:array, :text}, null: false
      add :bound_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec
      add :revoked_by, references(:principals, type: :uuid, on_delete: :nothing)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:device_credentials, [:principal_id])
    create unique_index(:device_credentials, [:key_digest], where: "key_digest IS NOT NULL")

    create constraint(:device_credentials, :revocation_is_attributed,
             check: "(revoked_at IS NULL) = (revoked_by IS NULL)"
           )

    create constraint(:device_credentials, :grant_is_grantable,
             check: "granted <@ ARRAY[#{quoted(@grantable)}]::text[]"
           )

    execute(immutable_grant_function(), "DROP FUNCTION credential_grant_is_immutable()")

    execute(
      """
      CREATE TRIGGER credential_grant_is_immutable
        AFTER UPDATE OF granted ON device_credentials
        FOR EACH ROW EXECUTE FUNCTION credential_grant_is_immutable();
      """,
      "DROP TRIGGER credential_grant_is_immutable ON device_credentials"
    )

    # One credential per device row, carrying everything that row already said.
    # The grant is the whole of what the principal's role may grant, because §4.2
    # makes a grant a subset of the role and a row that recorded no narrowing was
    # not narrowed; any smaller choice would invent one.
    #
    # There is no ELSE, so a device held by the System principal yields NULL
    # against a NOT NULL column and the migration stops. spec-06 §6.1 puts System
    # outside §3's authentication path, so such a row is a defect and a person
    # decides what to do about it.
    execute """
    INSERT INTO device_credentials
      (device_id, principal_id, key_digest, granted, bound_at, revoked_at, revoked_by,
       inserted_at, updated_at)
    SELECT d.id, d.principal_id, d.key_digest,
           CASE p.role
             WHEN 'administrator' THEN ARRAY[#{quoted(@grantable)}]
             WHEN 'member' THEN ARRAY[#{quoted(@grantable)}]
           END,
           d.bound_at, d.revoked_at, d.revoked_by, d.inserted_at, d.updated_at
    FROM devices d JOIN principals p ON p.id = d.principal_id
    """

    for {table, column} <- @referring do
      execute(repoint(table, column, :device_credentials), repoint(table, column, :devices))
    end

    drop constraint(:devices, :revocation_is_attributed)

    alter table(:devices) do
      remove :principal_id
      remove :bound_at
      remove :revoked_at
      remove :revoked_by
      remove :key_digest
    end
  end

  def down do
    alter table(:devices) do
      add :principal_id, references(:principals, type: :uuid, on_delete: :nothing)
      add :bound_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      add :revoked_by, references(:principals, type: :uuid, on_delete: :nothing)
      add :key_digest, :text
    end

    # Nothing records which principal the one-principal model would bind a device
    # to where it holds several credentials. Choosing one would invent it and
    # dropping the others would destroy history this direction has no mandate to
    # destroy, so it stops and names the device.
    execute """
    DO $$
    DECLARE shared uuid;
    BEGIN
      SELECT device_id INTO shared FROM device_credentials
        GROUP BY device_id HAVING count(*) > 1 LIMIT 1;

      IF shared IS NOT NULL THEN
        RAISE EXCEPTION 'device % holds credentials for several principals', shared;
      END IF;
    END $$;
    """

    execute """
    UPDATE devices d SET
      principal_id = c.principal_id,
      bound_at = c.bound_at,
      revoked_at = c.revoked_at,
      revoked_by = c.revoked_by,
      key_digest = c.key_digest
    FROM device_credentials c WHERE c.device_id = d.id
    """

    execute "DELETE FROM devices WHERE principal_id IS NULL"

    alter table(:devices) do
      modify :principal_id, :uuid, null: false
      modify :bound_at, :utc_datetime_usec, null: false
    end

    create unique_index(:devices, [:id, :principal_id])
    create unique_index(:devices, [:key_digest], where: "key_digest IS NOT NULL")
    create index(:devices, [:principal_id])

    create constraint(:devices, :revocation_is_attributed,
             check: "(revoked_at IS NULL) = (revoked_by IS NULL)"
           )

    for {table, column} <- @referring do
      execute(repoint(table, column, :devices))
    end

    execute "DROP TRIGGER credential_grant_is_immutable ON device_credentials"
    execute "DROP FUNCTION credential_grant_is_immutable()"

    drop table(:device_credentials)
  end

  defp repoint(table, column, :device_credentials) do
    """
    ALTER TABLE #{table}
      DROP CONSTRAINT #{table}_#{column}_fkey,
      ADD CONSTRAINT #{table}_#{column}_fkey
        FOREIGN KEY (#{column}, principal_id)
        REFERENCES device_credentials(device_id, principal_id)
    """
  end

  defp repoint(table, column, :devices) do
    """
    ALTER TABLE #{table}
      DROP CONSTRAINT #{table}_#{column}_fkey,
      ADD CONSTRAINT #{table}_#{column}_fkey
        FOREIGN KEY (#{column}, principal_id)
        REFERENCES devices(id, principal_id)
    """
  end

  defp immutable_grant_function do
    """
    CREATE FUNCTION credential_grant_is_immutable() RETURNS trigger AS $$
    BEGIN
      IF NEW.granted IS DISTINCT FROM OLD.granted THEN
        RAISE EXCEPTION 'a credential''s grant does not change'
          USING ERRCODE = '23514', CONSTRAINT = 'credential_grant_is_immutable';
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """
  end

  defp quoted(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
