defmodule Pluteus.Corpus.Repo.Migrations.HoldTheMusicbrainzCore do
  use Ecto.Migration

  # spec-05 §9.1: music is matched by the identifiers it carries, answered from
  # MusicBrainz's core dump held locally. These are the publisher's own tables, column for
  # column in the order schema 31's CreateTables.sql gives them, because the dump is each
  # table's COPY output with no column list and is loaded the same way.
  #
  # The publisher's CHECK constraints are its own integrity rules and are not repeated:
  # what is held is what the dump says, and a dump that broke them is the publisher's to
  # answer for. Only what a lookup needs is constrained here, and it is indexed after each
  # table is loaded, by the importer, since an index built row by row over the track table
  # costs far more than one built once over the loaded rows.
  #
  # An import loads a staging schema shaped like this one and exchanges the two, so these
  # tables are the snapshot in use and nothing else (§5.7).
  def up do
    execute "CREATE SCHEMA musicbrainz"

    execute """
    CREATE TABLE musicbrainz.recording (
      id integer NOT NULL,
      gid uuid NOT NULL,
      name text NOT NULL,
      artist_credit integer NOT NULL,
      length integer,
      comment text NOT NULL,
      edits_pending integer NOT NULL,
      last_updated timestamptz,
      video boolean NOT NULL
    )
    """

    execute """
    CREATE TABLE musicbrainz.track (
      id integer NOT NULL,
      gid uuid NOT NULL,
      recording integer NOT NULL,
      medium integer NOT NULL,
      position integer NOT NULL,
      number text NOT NULL,
      name text NOT NULL,
      artist_credit integer NOT NULL,
      length integer,
      edits_pending integer NOT NULL,
      last_updated timestamptz,
      is_data_track boolean NOT NULL
    )
    """

    execute """
    CREATE TABLE musicbrainz.medium (
      id integer NOT NULL,
      release integer NOT NULL,
      position integer NOT NULL,
      format integer,
      name text NOT NULL,
      edits_pending integer NOT NULL,
      last_updated timestamptz,
      track_count integer NOT NULL,
      gid uuid NOT NULL
    )
    """

    execute """
    CREATE TABLE musicbrainz.medium_cdtoc (
      id integer NOT NULL,
      medium integer NOT NULL,
      cdtoc integer NOT NULL,
      edits_pending integer NOT NULL,
      last_updated timestamptz
    )
    """

    execute """
    CREATE TABLE musicbrainz.cdtoc (
      id integer NOT NULL,
      discid text NOT NULL,
      freedb_id text NOT NULL,
      track_count integer NOT NULL,
      leadout_offset integer NOT NULL,
      track_offset integer[] NOT NULL,
      created timestamptz
    )
    """

    execute """
    CREATE TABLE musicbrainz.release (
      id integer NOT NULL,
      gid uuid NOT NULL,
      name text NOT NULL,
      artist_credit integer NOT NULL,
      release_group integer NOT NULL,
      status integer,
      packaging integer,
      language integer,
      script integer,
      barcode text,
      comment text NOT NULL,
      edits_pending integer NOT NULL,
      quality smallint NOT NULL,
      last_updated timestamptz
    )
    """

    execute """
    CREATE TABLE musicbrainz.release_group (
      id integer NOT NULL,
      gid uuid NOT NULL,
      name text NOT NULL,
      artist_credit integer NOT NULL,
      type integer,
      comment text NOT NULL,
      edits_pending integer NOT NULL,
      last_updated timestamptz
    )
    """

    execute """
    CREATE TABLE musicbrainz.work (
      id integer NOT NULL,
      gid uuid NOT NULL,
      name text NOT NULL,
      type integer,
      comment text NOT NULL,
      edits_pending integer NOT NULL,
      last_updated timestamptz
    )
    """

    execute """
    CREATE TABLE musicbrainz.isrc (
      id integer NOT NULL,
      recording integer NOT NULL,
      isrc text NOT NULL,
      edits_pending integer NOT NULL,
      created timestamptz
    )
    """

    # An identifier merged into another stays answerable: the redirect names the row it
    # now belongs to.
    for entity <- ~w(recording track release release_group work) do
      execute """
      CREATE TABLE musicbrainz.#{entity}_gid_redirect (
        gid uuid NOT NULL,
        new_id integer NOT NULL,
        created timestamptz
      )
      """
    end
  end

  def down do
    execute "DROP SCHEMA musicbrainz CASCADE"
  end
end
