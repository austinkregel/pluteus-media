defmodule Pluteus.Repo.Migrations.CreatePrincipalsAndEvents do
  use Ecto.Migration

  @agent_kinds ~w(person collective_agent)

  def change do
    # §10.1. A principal is an identity that uses the system, which LRM §2.1
    # places outside the model — so this is not a res. It carries §4.1's
    # identifier format all the same, because every identifier here does.
    #
    # `role` has no check constraint: §17 makes the role set seed data, and the
    # permissions each role carries are normative in spec-06 rather than here.
    create table(:principals, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :role, :string, null: false

      # §10.1 lets a principal name the LRM person it corresponds to. The link
      # is optional in both directions: the deployment itself acts as a
      # principal and is no person, and a person who assigns names but holds no
      # login is no principal.
      add :person_kind, :string

      timestamps(type: :utc_datetime_usec)
    end

    alter table(:principals) do
      add :person_id,
          references(:res,
            type: :uuid,
            column: :id,
            with: [person_kind: :kind],
            on_delete: :nothing
          )
    end

    create constraint(:principals, :person_link_is_whole,
             check: "(person_id IS NULL) = (person_kind IS NULL)"
           )

    create constraint(:principals, :principal_stands_for_a_person,
             check: "person_kind IS NULL OR person_kind = 'person'"
           )

    create unique_index(:principals, [:person_id])

    # §10.1. `sub` is unique only within an issuer, so the key is the composite.
    # It is a row rather than two columns on the principal because an issuer
    # change is then a write here and nothing else: every reference in the
    # system is to the principal's own identifier.
    create table(:principal_identities, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :principal_id, references(:principals, type: :uuid, on_delete: :nothing), null: false

      add :issuer, :text, null: false
      add :subject, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:principal_identities, [:issuer, :subject])
    create index(:principal_identities, [:principal_id])

    # §11.1. Descriptive records of what happened, carrying no notion of current
    # state. `type` is seed data (§11.3).
    create table(:events, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :principal_id, references(:principals, type: :uuid, on_delete: :nothing), null: false
      add :res_id, references(:res, type: :uuid, on_delete: :nothing), null: false

      add :type, :string, null: false
      add :occurred_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:events, [:principal_id, :occurred_at])
    create index(:events, [:res_id])

    # §11.1 separates resume position from event history: it is current state,
    # not a record of something that happened. The principal is half the key
    # because §11.2 stores progress against the principal who authenticated.
    create table(:resume_positions, primary_key: false) do
      add :principal_id, references(:principals, type: :uuid, on_delete: :nothing),
        primary_key: true,
        null: false

      add :res_id, references(:res, type: :uuid, on_delete: :nothing),
        primary_key: true,
        null: false

      add :position_ms, :bigint, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:resume_positions, :position_is_not_negative, check: "position_ms >= 0")

    # LRM-R14 is `Agent assigned Nomen`. The column has always pointed at res,
    # which admits a place or a time-span as an assigner. §10.1 keeps principals
    # out of it: the assigner is the agent, and an agent holding no login is one
    # the model must still accept.
    alter table(:nomens) do
      add :assigner_kind, :string
    end

    execute(
      "ALTER TABLE nomens DROP CONSTRAINT nomens_assigner_id_fkey",
      "ALTER TABLE nomens ADD CONSTRAINT nomens_assigner_id_fkey" <>
        " FOREIGN KEY (assigner_id) REFERENCES res(id)"
    )

    execute(
      "ALTER TABLE nomens ADD CONSTRAINT nomens_assigner_id_fkey" <>
        " FOREIGN KEY (assigner_id, assigner_kind) REFERENCES res(id, kind)",
      "ALTER TABLE nomens DROP CONSTRAINT nomens_assigner_id_fkey"
    )

    create constraint(:nomens, :assigner_link_is_whole,
             check: "(assigner_id IS NULL) = (assigner_kind IS NULL)"
           )

    create constraint(:nomens, :assigner_is_an_agent,
             check:
               "assigner_kind IS NULL OR assigner_kind IN " <>
                 "(#{Enum.map_join(@agent_kinds, ", ", &"'#{&1}'")})"
           )
  end
end
