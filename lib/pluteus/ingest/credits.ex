defmodule Pluteus.Ingest.Credits do
  @moduledoc """
  Credits: who a release says made it, and the agents they resolve to
  (spec-04 §6.4).

  Placement records credits as the tags state them and names no agent. The
  resolve stage, which runs on a schedule and never inside placement's
  transaction, resolves each credit carrying a MusicBrainz artist identifier:
  it asks MusicBrainz the artist's type once per identifier, creates a person
  for Person and a collective agent for Group, Orchestra or Choir, credits it
  as creator of the credit's work, and links the credit. Character and Other
  name no agent; a credit with no identifier stays a name.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Actor
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Credit
  alias Pluteus.Catalog.WorkCreator
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Finding
  alias Pluteus.Ingest.MusicBrainz
  alias Pluteus.Ingest.MusicBrainzArtist
  alias Pluteus.Ingest.Streams
  alias Pluteus.Principals
  alias Pluteus.Repo

  @kinds %{
    "Person" => :person,
    "Group" => :collective_agent,
    "Orchestra" => :collective_agent,
    "Choir" => :collective_agent
  }
  @attempts 3

  @doc """
  The credits a track's tags make, as `{name, musicbrainz_id}` in order, for a
  role: `:artist` from `artists` or else `artist`, paired with
  `musicbrainz_artistid`; `:album_artist` from `album_artist`, paired with
  `musicbrainz_albumartistid`.

  Identifiers pair with names by position only where every identifier is one
  and the counts agree; otherwise none is paired.
  """
  @spec from_tags(map(), :artist | :album_artist) :: [{String.t(), Ecto.UUID.t() | nil}]
  def from_tags(tags, :artist) do
    names = values(Streams.first(tags, ["artists"]) || tags["artist"])
    pair(names, values(tags["musicbrainz_artistid"]))
  end

  def from_tags(tags, :album_artist) do
    names = values(Streams.first(tags, ["album_artist", "albumartist", "album artist"]))
    pair(names, values(tags["musicbrainz_albumartistid"]))
  end

  defp values(nil), do: []

  defp values(value) do
    value |> String.split(";") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp pair(names, identifiers) do
    if length(names) == length(identifiers) and
         Enum.all?(identifiers, &match?({:ok, _}, Ecto.UUID.cast(&1))) do
      Enum.zip(names, Enum.map(identifiers, &String.downcase/1))
    else
      Enum.map(names, &{&1, nil})
    end
  end

  @doc """
  Records a work's credits in a role, with automatic provenance. Runs inside
  placement's transaction and reaches nothing outside the database.
  """
  @spec record(Ecto.UUID.t(), :artist | :album_artist, [{String.t(), Ecto.UUID.t() | nil}]) :: :ok
  def record(work_id, role, credits) do
    credits
    |> Enum.with_index(1)
    |> Enum.each(fn {{name, musicbrainz_id}, position} ->
      {:ok, _} =
        %Credit{}
        |> Credit.changeset(%{
          work_id: work_id,
          role: role,
          position: position,
          name: String.normalize(name, :nfc),
          musicbrainz_id: musicbrainz_id,
          provenance: :automatic
        })
        |> Repo.insert()
    end)
  end

  @spec credits_of(Ecto.UUID.t()) :: [Credit.t()]
  def credits_of(work_id) do
    Repo.all(from c in Credit, where: c.work_id == ^work_id, order_by: [c.role, c.position])
  end

  @doc """
  One pass of the resolve stage.

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

    if client == MusicBrainz and is_nil(MusicBrainz.contact()) do
      {:error, :no_contact_configured}
    else
      looked_up =
        due_identifiers()
        |> Enum.with_index()
        |> Enum.map(fn {musicbrainz_id, index} ->
          {musicbrainz_id, look_up_in_turn(index, interval, client, musicbrainz_id)}
        end)

      link_known()
      {:ok, looked_up}
    end
  end

  # Identifiers some unlinked credit carries that MusicBrainz has not yet
  # answered for, and that no open finding holds back.
  defp due_identifiers do
    answered =
      from a in MusicBrainzArtist, where: not is_nil(a.looked_up_at), select: a.musicbrainz_id

    blocked =
      from f in Finding,
        where: f.stage == :credit and is_nil(f.cleared_at),
        select: type(f.musicbrainz_id, Ecto.UUID)

    Repo.all(
      from c in Credit,
        where: not is_nil(c.musicbrainz_id) and is_nil(c.agent_id),
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
        agent_id = create_agent(Map.get(@kinds, type), musicbrainz_id)

        row
        |> Ecto.Changeset.change(type: type, agent_id: agent_id, looked_up_at: DateTime.utc_now())
        |> Repo.insert_or_update!()

        if agent_id, do: :agent, else: :no_agent_kind

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

  defp create_agent(nil, _musicbrainz_id), do: nil

  defp create_agent(kind, musicbrainz_id) do
    name =
      Repo.one!(
        from c in Credit,
          where: c.musicbrainz_id == ^musicbrainz_id,
          order_by: c.id,
          limit: 1,
          select: c.name
      )

    Actor.as(Principals.system!().id, fn ->
      {:ok, %{res: agent}} =
        Catalog.create_named_res(kind, %{nomen_string: name, provenance: :automatic})

      {:ok, _} =
        Catalog.create_nomen(%{
          res_id: agent.id,
          nomen_string: musicbrainz_id,
          scheme: "musicbrainz",
          provenance: :automatic
        })

      agent.id
    end)
  end

  # Every unlinked credit whose identifier has an agent is linked to it, and the
  # agent credited as creator of the credit's work.
  defp link_known do
    pending =
      Repo.all(
        from c in Credit,
          join: a in MusicBrainzArtist,
          on: a.musicbrainz_id == c.musicbrainz_id,
          join: r in Catalog.Res,
          on: r.id == a.agent_id,
          where: is_nil(c.agent_id),
          select: {c, r}
      )

    Actor.as(Principals.system!().id, fn ->
      Enum.each(pending, fn {credit, agent} -> link(credit, agent) end)
    end)
  end

  defp link(credit, agent) do
    credit
    |> Credit.changeset(%{agent_id: agent.id, agent_kind: agent.kind})
    |> Repo.update!()

    credited =
      Repo.exists?(
        from w in WorkCreator, where: w.work_id == ^credit.work_id and w.agent_id == ^agent.id
      )

    unless credited, do: {:ok, _} = Catalog.credit_creator(credit.work_id, agent.id)
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
