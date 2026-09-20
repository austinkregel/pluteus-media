defmodule Pluteus.Repo.Migrations.NameAnArtistForEveryCredit do
  use Ecto.Migration

  # spec-01 §3.1. An agent known by the name it performs or is credited under,
  # of whom it is not yet known whether they are a person or a collective
  # agent. It is recorded at the superclass because its subclass has not been
  # determined, rather than guessed at and recorded as fact.
  @kinds ~w(res work expression manifestation item digital_item asset person collective_agent
            artist nomen place time_span address annotation)
  @prior_kinds @kinds -- ~w(artist)
  @agents ~w(person collective_agent artist)
  @prior_agents @agents -- ~w(artist)

  def up do
    drop constraint(:res, :kind_must_be_known)
    create constraint(:res, :kind_must_be_known, check: in_list("kind", @kinds))

    # Narrowing an artist is the one change of kind the model permits, and the
    # store is the authority on that: a write that bypasses the catalog cannot
    # turn a work into a person, nor widen an agent back to an artist.
    execute """
    CREATE FUNCTION refuse_kind_change() RETURNS trigger AS $$
    BEGIN
      IF NEW.kind <> OLD.kind
         AND NOT (OLD.kind = 'artist' AND NEW.kind IN ('person', 'collective_agent')) THEN
        RAISE EXCEPTION 'a res does not change kind: % to %', OLD.kind, NEW.kind;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER refuse_kind_change
      BEFORE UPDATE ON res
      FOR EACH ROW EXECUTE FUNCTION refuse_kind_change();
    """

    drop constraint(:credits, :credited_agent_is_an_agent)

    create constraint(:credits, :credited_agent_is_an_agent,
             check: "agent_kind IS NULL OR #{in_list("agent_kind", @agents)}"
           )

    drop constraint(:work_creators, :creator_is_an_agent)
    create constraint(:work_creators, :creator_is_an_agent, check: in_list("agent_kind", @agents))

    # Narrowing an artist to a person or a collective agent changes its kind.
    # The rows naming it repeat that kind under a composite key, so they follow
    # the change rather than refuse it, and what was credited to the artist
    # stays credited to it.
    follow_kind(:credits, :agent_id, true)
    follow_kind(:work_creators, :agent_id, true)

    # spec-04 §6.4. The key each artist was created under: its MusicBrainz
    # artist identifier, or its name where it carries none. The key is unique,
    # as a release key is, so two placements naming one artist create one
    # artist. The reference is to res, which survives a purge as a tombstone,
    # so a key whose artist has gone is recognizable as such rather than
    # dangling.
    create table(:artist_keys, primary_key: false) do
      add :key, :text, primary_key: true
      add :artist_id, references(:res, type: :uuid, on_delete: :nothing)

      timestamps(type: :utc_datetime_usec)
    end
  end

  def down do
    drop table(:artist_keys)

    execute "DROP TRIGGER refuse_kind_change ON res"
    execute "DROP FUNCTION refuse_kind_change()"

    follow_kind(:work_creators, :agent_id, false)
    follow_kind(:credits, :agent_id, false)

    drop constraint(:work_creators, :creator_is_an_agent)

    create constraint(:work_creators, :creator_is_an_agent,
             check: in_list("agent_kind", @prior_agents)
           )

    drop constraint(:credits, :credited_agent_is_an_agent)

    create constraint(:credits, :credited_agent_is_an_agent,
             check: "agent_kind IS NULL OR #{in_list("agent_kind", @prior_agents)}"
           )

    drop constraint(:res, :kind_must_be_known)
    create constraint(:res, :kind_must_be_known, check: in_list("kind", @prior_kinds))
  end

  defp follow_kind(table, column, cascade?) do
    on_update = if cascade?, do: " ON UPDATE CASCADE", else: ""

    execute "ALTER TABLE #{table} DROP CONSTRAINT #{table}_#{column}_fkey"

    execute """
    ALTER TABLE #{table} ADD CONSTRAINT #{table}_#{column}_fkey
      FOREIGN KEY (#{column}, agent_kind) REFERENCES res(id, kind)#{on_update}
    """
  end

  defp in_list(column, values) do
    "#{column} IN (#{Enum.map_join(values, ", ", &"'#{&1}'")})"
  end
end
