defmodule Pluteus.Repo.Migrations.NameTheLevelAMusicbrainzIdentifierIdentifies do
  use Ecto.Migration

  # spec-05 §4.1: a scheme identifies one level, and MusicBrainz has six identifier
  # types besides its artists'. Placement has only ever written an artist's identifier,
  # so every nomen in the bare scheme is one, and it is renamed to say so.
  #
  # Catalog writes are attributed, and the trigger refuses one with no actor. These were
  # placement's, which acts as the System principal, so the rename is attributed to it.
  def up, do: move_scheme("musicbrainz", "musicbrainz_artist")

  def down, do: move_scheme("musicbrainz_artist", "musicbrainz")

  defp move_scheme(from, to) do
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM nomens WHERE scheme = '#{from}') THEN
        PERFORM set_config(
          'pluteus.actor',
          (SELECT id::text FROM principals WHERE role = 'system'),
          true
        );

        UPDATE nomens SET scheme = '#{to}' WHERE scheme = '#{from}';
      END IF;
    END $$;
    """
  end
end
