defmodule Pluteus.Ingest.Credits do
  @moduledoc """
  Credits: who a release says made it, and the artists they name (spec-04
  §6.4).

  Placement records credits as the tags state them, and every credit names an
  artist from the moment it is placed: one per MusicBrainz artist identifier,
  one per name for a credit carrying none, created where none exists and
  credited as creator of the credit's work. An artist who has made a record can
  be starred, rated and browsed whether or not a music database knows of them.

  The resolve stage, which runs on a schedule and never inside placement's
  transaction, asks MusicBrainz the type of each artist carrying an identifier
  and narrows it: a person for Person, a collective agent for Group, Orchestra
  or Choir. Character and Other stay artists, as does an artist with no
  identifier, until matching or a person says what it is.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Actor
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Credit
  alias Pluteus.Catalog.Res
  alias Pluteus.Catalog.WorkCreator
  alias Pluteus.Ingest
  alias Pluteus.Ingest.ArtistKey
  alias Pluteus.Ingest.Finding
  alias Pluteus.Ingest.MusicBrainz
  alias Pluteus.Ingest.MusicBrainzArtist
  alias Pluteus.Ingest.Streams
  alias Pluteus.Lifecycle
  alias Pluteus.Principals
  alias Pluteus.Repo

  @kinds %{
    "Person" => :person,
    "Group" => :collective_agent,
    "Orchestra" => :collective_agent,
    "Choir" => :collective_agent
  }
  @attempts 3

  # The separator Picard writes into the fields it owns. `artists` and the identifier
  # fields are structured rather than display text, and carry it whatever the container is.
  @structured ";"

  @doc """
  The credits a track's tags make, as `{name, musicbrainz_id}` in order, for a
  role: `:artist` from `artists` or else `artist`, paired with
  `musicbrainz_artistid`; `:album_artist` from `album_artist`, paired with
  `musicbrainz_albumartistid`.

  Identifiers pair with names by position only where every identifier is one
  and the counts agree; otherwise none is paired.

  `separator` is the container's, from `Pluteus.Ingest.Registry.tag_separator/1`, and
  applies to the display fields alone. A nil separator takes the field whole.
  """
  @spec from_tags(map(), :artist | :album_artist, String.t() | nil) ::
          [{String.t(), Ecto.UUID.t() | nil}]
  def from_tags(tags, role, separator \\ nil)

  def from_tags(tags, :artist, separator) do
    names =
      case Streams.first(tags, ["artists"]) do
        nil -> values(tags["artist"], separator)
        structured -> values(structured, @structured)
      end

    pair(names, values(tags["musicbrainz_artistid"], @structured))
  end

  def from_tags(tags, :album_artist, separator) do
    names =
      tags
      |> Streams.first(["album_artist", "albumartist", "album artist"])
      |> values(separator)

    pair(names, values(tags["musicbrainz_albumartistid"], @structured))
  end

  @doc """
  The names the first of these tags carries, as credits naming no identifier.

  No convention pairs a MusicBrainz identifier with an author or a narrator, so a credit
  read this way carries a name and nothing more, and matching is what may later say who
  the name is.

  `separator` is the container's. A reading of five people names them in one field, and
  which character stands between them is the container's convention rather than the
  field's.
  """
  @spec named_by(map(), [String.t()], String.t() | nil) :: [{String.t(), nil}]
  def named_by(tags, tag_names, separator \\ nil) do
    tags |> Streams.first(tag_names) |> values(separator) |> Enum.map(&{&1, nil})
  end

  defp values(nil, _separator), do: []

  # A container the registry names no separator for states one value, so the field is a
  # name that may itself hold a comma rather than a list that happens to.
  defp values(value, nil), do: trimmed([value])

  defp values(value, separator), do: value |> String.split(separator) |> trimmed()

  defp trimmed(values), do: values |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp pair(names, identifiers) do
    if length(names) == length(identifiers) and
         Enum.all?(identifiers, &match?({:ok, _}, Ecto.UUID.cast(&1))) do
      Enum.zip(names, Enum.map(identifiers, &String.downcase/1))
    else
      Enum.map(names, &{&1, nil})
    end
  end

  @doc """
  Records a res's credits in a role, with automatic provenance, each naming
  the artist it credits. Runs inside placement's transaction and reaches
  nothing outside the database.

  The subject is `{:work, id}` or `{:expression, id}`, and which it is decides what a
  credit means: an author of a text is credited on the work and a narrator of a reading of
  it on the expression (§6.9).
  """
  @spec record({:work | :expression, Ecto.UUID.t()}, atom(), [
          {String.t(), Ecto.UUID.t() | nil}
        ]) :: :ok
  def record(subject, role, credits) do
    credits =
      Enum.map(credits, fn {name, musicbrainz_id} -> {normalize(name), musicbrainz_id} end)

    artists = artists_for(credits)

    credits
    |> Enum.with_index(1)
    |> Enum.each(fn {{name, musicbrainz_id}, position} ->
      artist = Map.fetch!(artists, {name, musicbrainz_id})

      {:ok, _} =
        %Credit{}
        |> Credit.changeset(
          Map.merge(subject(subject), %{
            role: role,
            position: position,
            name: name,
            musicbrainz_id: musicbrainz_id,
            agent_id: artist.id,
            agent_kind: artist.kind,
            provenance: :automatic
          })
        )
        |> Repo.insert()

      creator_of(subject, artist.id)
    end)
  end

  defp subject({:work, work_id}), do: %{work_id: work_id}
  defp subject({:expression, expression_id}), do: %{expression_id: expression_id}

  # LRM's creator relation holds between an agent and a work. A narrator did not make the
  # text, so an expression credit records the credit and no creator relation; the agent is
  # a res all the same, and can be starred, rated and browsed.
  defp creator_of({:work, work_id}, agent_id), do: credit_creator(work_id, agent_id)
  defp creator_of({:expression, _expression_id}, _agent_id), do: :ok

  # A stored credit names one level or the other, which the database enforces, so there is
  # no third case for a row to be in.
  defp subject_of(%Credit{work_id: work_id}) when not is_nil(work_id), do: {:work, work_id}

  defp subject_of(%Credit{expression_id: expression_id}) when not is_nil(expression_id),
    do: {:expression, expression_id}

  # The artists a work's credits name, in key order. A track crediting two
  # artists and another crediting the same two in the other order take their
  # keys in one order, and queue rather than deadlock.
  defp artists_for(credits) do
    credits
    |> Enum.uniq()
    |> Enum.sort_by(fn {name, musicbrainz_id} -> key_for(name, musicbrainz_id) end)
    |> Map.new(fn {name, musicbrainz_id} ->
      {{name, musicbrainz_id}, artist_for(name, musicbrainz_id)}
    end)
  end

  @doc """
  The artist a credit names: the one for its MusicBrainz artist identifier, or
  the one for its name where it carries none, created where none exists.

  An artist for an identifier and an artist for a name are never the same
  artist, even where the names agree: matching or a person links them. A key
  whose artist has since been recycled or purged names a new one, as a release
  key does.
  """
  @spec artist_for(String.t(), Ecto.UUID.t() | nil) :: Res.t()
  def artist_for(name, musicbrainz_id) do
    name = normalize(name)
    key = key_for(name, musicbrainz_id)
    now = DateTime.utc_now()

    {inserted, _} =
      Repo.insert_all(ArtistKey, [%{key: key, inserted_at: now, updated_at: now}],
        on_conflict: :nothing,
        conflict_target: :key
      )

    # Held for the rest of the transaction, so two placements naming one artist queue on it
    # rather than each creating an artist for the same name. The lock is taken on the read,
    # because an insert that conflicts locks nothing, and it is taken before the artist is
    # created, because `create_artist/3` updates this row once it has one.
    existing = Repo.one!(from k in ArtistKey, where: k.key == ^key, lock: "FOR UPDATE")

    if inserted == 0 and live?(existing.artist_id),
      do: Repo.get!(Res, existing.artist_id),
      else: create_artist(existing, name, musicbrainz_id)
  end

  defp key_for(name, nil), do: "name:" <> name
  defp key_for(_name, musicbrainz_id), do: "mbid:" <> musicbrainz_id

  defp normalize(name), do: String.normalize(name, :nfc)

  defp live?(nil), do: false
  defp live?(res_id), do: match?({:live, _}, Lifecycle.state(res_id))

  defp create_artist(artist_key, name, musicbrainz_id) do
    {:ok, %{res: artist}} =
      Catalog.create_named_res(:artist, %{nomen_string: name, provenance: :automatic})

    if musicbrainz_id do
      {:ok, _} =
        Catalog.create_nomen(%{
          res_id: artist.id,
          nomen_string: musicbrainz_id,
          scheme: "musicbrainz",
          provenance: :automatic
        })
    end

    artist_key |> Ecto.Changeset.change(artist_id: artist.id) |> Repo.update!()
    artist
  end

  defp credit_creator(work_id, agent_id) do
    credited =
      Repo.exists?(
        from w in WorkCreator, where: w.work_id == ^work_id and w.agent_id == ^agent_id
      )

    unless credited, do: {:ok, _} = Catalog.credit_creator(work_id, agent_id)
  end

  @doc """
  The credits about one res, whether they name it as a work or as an expression.
  """
  @spec credits_of(Ecto.UUID.t()) :: [Credit.t()]
  def credits_of(res_id) do
    Repo.all(
      from c in Credit,
        where: c.work_id == ^res_id or c.expression_id == ^res_id,
        order_by: [c.role, c.position]
    )
  end

  @doc """
  One pass of the resolve stage: an artist for every credit that has none, and
  a MusicBrainz lookup narrowing each artist whose identifier it answers for.

  Options:

    * `:client` — the module that asks MusicBrainz; the real one unless given.
    * `:interval_ms` — the pause between two requests, one second unless given,
      which is MusicBrainz's limit.

  Returns `{:error, :no_contact_configured}`, and asks nothing, where the real
  client is to be used and no contact is configured.
  """
  @spec resolve_due(keyword()) ::
          {:ok, [{Ecto.UUID.t(), atom()}]} | {:error, :no_contact_configured}
  def resolve_due(opts \\ []) do
    client = Keyword.get(opts, :client, MusicBrainz)
    interval = Keyword.get(opts, :interval_ms, 1_000)

    # Naming an artist asks nothing of anyone, so a deployment configured with
    # no contact still gets every credit named; only the lookups wait.
    name_unnamed()

    if client == MusicBrainz and is_nil(MusicBrainz.contact()) do
      {:error, :no_contact_configured}
    else
      looked_up =
        due_identifiers()
        |> Enum.with_index()
        |> Enum.map(fn {musicbrainz_id, index} ->
          {musicbrainz_id, look_up_in_turn(index, interval, client, musicbrainz_id)}
        end)

      {:ok, looked_up}
    end
  end

  # A credit naming no artist is one placed before an artist was named for
  # every credit. It is given the artist its identifier or name calls for, by
  # the rule placement follows.
  defp name_unnamed do
    unnamed = Repo.all(from c in Credit, where: is_nil(c.agent_id), order_by: c.id)

    Actor.as(Principals.system!().id, fn ->
      Enum.each(unnamed, fn credit ->
        artist = artist_for(credit.name, credit.musicbrainz_id)

        credit
        |> Credit.changeset(%{agent_id: artist.id, agent_kind: artist.kind})
        |> Repo.update!()

        creator_of(subject_of(credit), artist.id)
      end)
    end)
  end

  # Identifiers carried by a credit whose artist is still an artist, that
  # MusicBrainz has not yet answered for, and that no open finding holds back.
  defp due_identifiers do
    answered =
      from a in MusicBrainzArtist, where: not is_nil(a.looked_up_at), select: a.musicbrainz_id

    blocked =
      from f in Finding,
        where: f.stage == :credit and is_nil(f.cleared_at),
        select: type(f.musicbrainz_id, Ecto.UUID)

    Repo.all(
      from c in Credit,
        where: not is_nil(c.musicbrainz_id) and c.agent_kind == :artist,
        where: c.musicbrainz_id not in subquery(answered),
        where: c.musicbrainz_id not in subquery(blocked),
        distinct: true,
        order_by: c.musicbrainz_id,
        select: c.musicbrainz_id
    )
  end

  # Every request after the first waits the interval, keeping to MusicBrainz's
  # limit of one a second.
  defp look_up_in_turn(0, _interval, client, musicbrainz_id), do: look_up(client, musicbrainz_id)

  defp look_up_in_turn(_index, interval, client, musicbrainz_id) do
    Process.sleep(interval)
    look_up(client, musicbrainz_id)
  end

  defp look_up(client, musicbrainz_id) do
    row =
      Repo.get(MusicBrainzArtist, musicbrainz_id) ||
        %MusicBrainzArtist{musicbrainz_id: musicbrainz_id}

    case client.artist_type(musicbrainz_id) do
      {:ok, type} ->
        artist_id = Repo.get!(ArtistKey, "mbid:" <> musicbrainz_id).artist_id
        outcome = narrow(Map.get(@kinds, type), artist_id)

        row
        |> Ecto.Changeset.change(
          type: type,
          agent_id: artist_id,
          looked_up_at: DateTime.utc_now()
        )
        |> Repo.insert_or_update!()

        outcome

      {:error, :not_found} ->
        finding(musicbrainz_id, "musicbrainz_artist_not_found", true, %{})
        :not_found

      {:error, :transient, reason} ->
        attempts = row.attempts + 1
        row |> Ecto.Changeset.change(attempts: attempts) |> Repo.insert_or_update!()

        if attempts >= @attempts do
          finding(musicbrainz_id, "transient_failure_exhausted", false, %{reason: inspect(reason)})

          :exhausted
        else
          :transient
        end
    end
  end

  # A type MusicBrainz names no agent kind for — Character, Other — leaves the
  # artist an artist. Narrowing keeps its identifier, so the credits naming it
  # and the works it is credited with follow it without being rewritten.
  defp narrow(nil, _artist_id), do: :stays_an_artist

  defp narrow(kind, artist_id) do
    Actor.as(Principals.system!().id, fn ->
      {:ok, _} = Catalog.narrow(artist_id, kind)
      :narrowed
    end)
  end

  defp finding(musicbrainz_id, kind, permanent, detail) do
    Ingest.record_finding(%{
      stage: :credit,
      kind: kind,
      permanent: permanent,
      detail: detail,
      musicbrainz_id: musicbrainz_id
    })
  end
end
