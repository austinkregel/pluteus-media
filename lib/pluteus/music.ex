defmodule Pluteus.Music do
  @moduledoc """
  The catalog read as music (spec-07 §6.4): albums, songs and artists.

  An album is a release manifestation: one embodying an expression of a work
  whose category is the release category, and not itself a part of another
  manifestation, since a release's media embody the same aggregating
  expression. Its songs are the track manifestations that are parts of its
  media, in disc and track order. An artist is the agent a credit names
  (spec-04 §6.4), which is a res like any other and can be starred and rated
  as one.

  A credit that names no artist yet is not shown as one. Placement names an
  artist for every credit it writes, and the credit stage names one for any
  credit that has none, so this is a catalog waiting for that pass rather than
  an artist the household cannot reach.

  Names are resolved under the profile given. Only live res appear: a recycled
  or purged album, medium or track is left out wherever it would be shown.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Annotations
  alias Pluteus.Catalog.Address
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.AssetRole
  alias Pluteus.Catalog.Association
  alias Pluteus.Catalog.Credit
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Embodiment
  alias Pluteus.Catalog.Expression
  alias Pluteus.Catalog.Manifestation
  alias Pluteus.Catalog.ManifestationPart
  alias Pluteus.Catalog.Nomen
  alias Pluteus.Catalog.Profile
  alias Pluteus.Catalog.Res
  alias Pluteus.Catalog.Resolution
  alias Pluteus.Ingest.Place
  alias Pluteus.Ingest.Registry
  alias Pluteus.Ingest.Streams
  alias Pluteus.Lifecycle.RecycledRes
  alias Pluteus.Lifecycle.Tombstone
  alias Pluteus.Repo

  defmodule Artist do
    @moduledoc "An artist: the agent a credit names."
    defstruct [:id, :name, :musicbrainz_id]
    @type t :: %__MODULE__{}
  end

  defmodule Song do
    @moduledoc "A track manifestation as a song."
    defstruct [
      :id,
      :work_id,
      :album_id,
      :title,
      :disc,
      :track,
      :artists,
      :digital_item_id,
      :master,
      :original,
      :suffix,
      :extent,
      :probe,
      :created,
      :duration_s,
      :bpm
    ]

    @type t :: %__MODULE__{}
  end

  defmodule Album do
    @moduledoc "A release manifestation as an album, with its songs in order."
    defstruct [:id, :work_id, :name, :artists, :songs, :created]
    @type t :: %__MODULE__{}
  end

  # --- Albums -----------------------------------------------------------------

  @doc """
  Every live album's identifier, in identifier order.
  """
  @spec album_ids() :: [Ecto.UUID.t()]
  def album_ids do
    ranks = Enum.map(Nomen.provenance_rank(), &Atom.to_string/1)

    Repo.all(
      from m in Manifestation,
        join: e in Embodiment,
        on: e.manifestation_id == m.id,
        join: x in Expression,
        on: x.id == e.expression_id,
        where:
          fragment(
            """
            (SELECT c.value FROM categories c
               WHERE c.res_id = ? AND c.scheme = ?
               ORDER BY array_position(?::text[], c.provenance::text) LIMIT 1) = ?
            """,
            x.work_id,
            ^Place.category_scheme(),
            ^ranks,
            ^Registry.default_category(:release, nil)
          ),
        where: m.id not in subquery(from p in ManifestationPart, select: p.part_id),
        where: m.id not in subquery(recycled()),
        where: m.id not in subquery(purged()),
        distinct: true,
        order_by: m.id,
        select: m.id
    )
  end

  @doc """
  Every live album, with its songs.
  """
  @spec library(Profile.t()) :: [Album.t()]
  def library(profile), do: albums(album_ids(), profile)

  @doc """
  One live album with its songs, or nil where the identifier names none.
  """
  @spec album(Ecto.UUID.t(), Profile.t()) :: Album.t() | nil
  def album(album_id, profile) do
    if album_id in album_ids(), do: hd(albums([album_id], profile)), else: nil
  end

  @doc """
  One live song, with the album it is on, or nil where the identifier names
  none.
  """
  @spec song(Ecto.UUID.t(), Profile.t()) :: {Song.t(), Album.t()} | nil
  def song(song_id, profile) do
    with [album_id | _] <- albums_of([song_id]),
         %Album{} = album <- album(album_id, profile),
         %Song{} = song <- Enum.find(album.songs, &(&1.id == song_id)) do
      {song, album}
    else
      _none -> nil
    end
  end

  @doc """
  The songs with the given identifiers that are live, in the order given.
  """
  @spec songs([Ecto.UUID.t()], Profile.t()) :: [Song.t()]
  def songs(song_ids, profile) do
    by_id =
      song_ids
      |> albums_of()
      |> Enum.filter(&(&1 in album_ids()))
      |> albums(profile)
      |> Enum.flat_map(& &1.songs)
      |> Map.new(&{&1.id, &1})

    for id <- song_ids, Map.has_key?(by_id, id), do: by_id[id]
  end

  defp albums_of(song_ids) do
    Repo.all(
      from track in ManifestationPart,
        join: medium in ManifestationPart,
        on: medium.part_id == track.whole_id,
        where: track.part_id in ^song_ids,
        distinct: true,
        select: medium.whole_id
    )
  end

  @doc """
  Albums with their songs, for identifiers already known to be live albums.
  """
  @spec albums([Ecto.UUID.t()], Profile.t()) :: [Album.t()]
  def albums([], _profile), do: []

  def albums(album_ids, profile) do
    media = live_parts(album_ids)
    tracks = live_parts(Enum.map(media, &elem(&1, 1)))
    track_ids = Enum.map(tracks, &elem(&1, 1))

    works = works_of(album_ids ++ track_ids)
    credits = effective_credits(Map.values(works))
    items = digital_items_of(album_ids ++ track_ids)
    assets = assets_of(Map.values(items))
    probes = probes_of(album_ids ++ track_ids, items, assets)
    measurements = Annotations.current_bodies(track_ids, "measurements")
    agents = for {_key, list} <- credits, credit <- list, credit.agent_id, do: credit.agent_id
    masters = for {{_item, :normalized}, asset} <- assets, do: asset.id
    names = names(album_ids ++ track_ids ++ agents ++ masters, profile)
    created = created(album_ids ++ track_ids)
    extents = extents_of(track_ids)

    found = %{
      works: works,
      credits: credits,
      items: items,
      assets: assets,
      probes: probes,
      names: names,
      created: created,
      extents: extents,
      measurements: measurements
    }

    medium_of =
      Map.new(media, fn {album_id, medium_id, disc} -> {medium_id, {album_id, disc}} end)

    songs_by_album =
      tracks
      |> Enum.map(fn {medium_id, track_id, position} ->
        {album_id, disc} = medium_of[medium_id]
        song(track_id, album_id, disc, position, found)
      end)
      |> Enum.sort_by(&{&1.disc || 0, &1.track || 0, &1.id})
      |> Enum.group_by(& &1.album_id)

    Enum.map(album_ids, &album(&1, Map.get(songs_by_album, &1, []), found))
  end

  defp song(track_id, album_id, disc, position, found) do
    item = found.items[track_id]
    master = item && found.assets[{item, :normalized}]
    extent = found.extents[track_id]

    %Song{
      id: track_id,
      work_id: found.works[track_id],
      album_id: album_id,
      title: found.names[track_id],
      disc: disc,
      track: position,
      artists: artists(found.credits[{found.works[track_id], :artist}], found.names),
      digital_item_id: item,
      master: master,
      original: item && found.assets[{item, :acquired}],
      suffix: suffix(master, found.names),
      extent: extent,
      probe: found.probes[track_id] || (extent && found.probes[album_id]),
      created: found.created[track_id],
      duration_s: duration_s(extent, found.probes[track_id]),
      bpm: found.measurements[track_id]["tempo_bpm"]
    }
  end

  # An album credited to no album artist is credited to its songs' artists.
  defp album(album_id, songs, found) do
    album_artists =
      case artists(found.credits[{found.works[album_id], :album_artist}], found.names) do
        [] -> songs |> Enum.flat_map(& &1.artists) |> Enum.uniq_by(& &1.id)
        credited -> credited
      end

    %Album{
      id: album_id,
      work_id: found.works[album_id],
      name: found.names[album_id],
      artists: album_artists,
      songs: songs,
      created: found.created[album_id]
    }
  end

  # {whole, part, position} for each live part of the given wholes.
  defp live_parts(whole_ids) do
    Repo.all(
      from p in ManifestationPart,
        where: p.whole_id in ^whole_ids,
        where: p.part_id not in subquery(recycled()),
        where: p.part_id not in subquery(purged()),
        select: {p.whole_id, p.part_id, p.position}
    )
  end

  defp works_of(manifestation_ids) do
    Map.new(
      Repo.all(
        from e in Embodiment,
          join: x in Expression,
          on: x.id == e.expression_id,
          where: e.manifestation_id in ^manifestation_ids,
          order_by: e.expression_id,
          select: {e.manifestation_id, x.work_id}
      )
    )
  end

  # A member's correction outranks placement's credits of the same role: where
  # a work carries credits of several provenances in a role, only the most
  # authoritative are read.
  defp effective_credits(work_ids) do
    ranks = Nomen.provenance_rank()

    Repo.all(from c in Credit, where: c.work_id in ^work_ids)
    |> Enum.group_by(&{&1.work_id, &1.role})
    |> Map.new(fn {key, credits} ->
      best = Enum.min_by(credits, &Enum.find_index(ranks, fn p -> p == &1.provenance end))

      {key,
       credits
       |> Enum.filter(&(&1.provenance == best.provenance))
       |> Enum.sort_by(& &1.position)}
    end)
  end

  defp artists(nil, _names), do: []

  defp artists(credits, names) do
    credits
    |> Enum.filter(& &1.agent_id)
    |> Enum.map(fn %Credit{agent_id: agent_id} = credit ->
      %Artist{
        id: agent_id,
        name: names[agent_id] || credit.name,
        musicbrainz_id: credit.musicbrainz_id
      }
    end)
    |> Enum.uniq_by(& &1.id)
  end

  defp digital_items_of(manifestation_ids) do
    Map.new(
      Repo.all(
        from d in DigitalItem,
          where: d.manifestation_id in ^manifestation_ids,
          where: d.id not in subquery(recycled()),
          where: d.id not in subquery(purged()),
          order_by: [desc: d.id],
          select: {d.manifestation_id, d.id}
      )
    )
  end

  defp assets_of(digital_item_ids) do
    Map.new(
      Repo.all(
        from a in Asset,
          join: r in AssetRole,
          on: r.asset_id == a.id,
          where: a.digital_item_id in ^digital_item_ids,
          where: r.role_class in [:normalized, :acquired],
          where: a.id not in subquery(recycled()),
          where: a.id not in subquery(purged()),
          order_by: [desc: a.id],
          select: {{a.digital_item_id, r.role_class}, a}
      )
    )
  end

  # spec-04 §6.1 records a probe against the asset whose bytes it read, so the
  # reading for a manifestation is the one on the asset carrying its bytes. That is
  # the Acquired asset: normalization may re-encode, and what a client is told about
  # the release is what arrived.
  defp probes_of(manifestation_ids, items, assets) do
    acquired =
      Map.new(manifestation_ids, fn manifestation_id ->
        {manifestation_id, assets[{items[manifestation_id], :acquired}]}
      end)

    bodies =
      acquired
      |> Map.values()
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.id)
      |> Annotations.current_bodies("probe")

    Map.new(acquired, fn
      {manifestation_id, nil} -> {manifestation_id, nil}
      {manifestation_id, asset} -> {manifestation_id, bodies[asset.id]}
    end)
  end

  defp extents_of(track_ids) do
    Map.new(
      Repo.all(
        from a in Association,
          join: address in Address,
          on: address.id == a.subject_id,
          where: a.refinement == "extent-of" and a.object_id in ^track_ids,
          select: {a.object_id, {address.start_ms, address.end_ms}}
      )
    )
  end

  defp names(res_ids, profile) do
    res_ids
    |> Enum.uniq()
    |> Resolution.resolve_many(profile)
    |> Map.new(fn {id, nomen} -> {id, nomen.nomen_string} end)
  end

  defp created(res_ids) do
    Map.new(Repo.all(from r in Res, where: r.id in ^res_ids, select: {r.id, r.inserted_at}))
  end

  defp suffix(nil, _names), do: nil

  defp suffix(asset, names) do
    case Path.extname(names[asset.id] || "") do
      "." <> extension -> String.downcase(extension)
      "" -> nil
    end
  end

  defp duration_s({start_ms, end_ms}, _probe), do: div(end_ms - start_ms, 1000)
  defp duration_s(nil, nil), do: nil

  # A container that states no duration leaves the length unknown, which §5.2 reports as
  # an absence rather than as nothing playing for no time.
  defp duration_s(nil, probe) do
    case Streams.duration_ms(probe) do
      nil -> nil
      milliseconds -> div(milliseconds, 1000)
    end
  end

  # --- What a song's probe says ----------------------------------------------

  @doc """
  The genres a song's probe names, in order.
  """
  @spec genres(Song.t()) :: [String.t()]
  def genres(%Song{probe: probe}) do
    case Streams.tags(probe)["genre"] do
      nil -> []
      value -> value |> String.split(";") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end
  end

  @doc """
  The year a song's probe names, where it names one.
  """
  @spec year(Song.t()) :: pos_integer() | nil
  def year(%Song{probe: probe}) do
    with value when is_binary(value) <-
           Streams.first(Streams.tags(probe), ["date", "year", "originaldate", "releasedate"]),
         [_, digits] <- Regex.run(~r/\A(\d{4})/, value) do
      String.to_integer(digits)
    else
      _none -> nil
    end
  end

  @doc """
  The audio stream a song's probe found, which carries what the protocol asks
  of every song: its bit depth, sampling rate and channel count.
  """
  @spec audio_stream(Song.t()) :: map()
  def audio_stream(%Song{probe: nil}), do: %{}

  def audio_stream(%Song{probe: probe}) do
    probe |> Map.get("streams", []) |> Enum.find(%{}, &(&1["codec_type"] == "audio"))
  end

  @doc """
  A tag a song's probe read, where it carries one.
  """
  @spec tag(Song.t(), [String.t()]) :: String.t() | nil
  def tag(%Song{probe: probe}, keys), do: Streams.first(Streams.tags(probe), keys)

  @doc """
  A song's bit rate in kilobits a second, from its probe.
  """
  @spec bit_rate(Song.t()) :: non_neg_integer() | nil
  def bit_rate(%Song{probe: nil}), do: nil

  def bit_rate(%Song{probe: probe}) do
    case Integer.parse(get_in(probe, ["format", "bit_rate"]) || "") do
      {bits, _rest} -> div(bits, 1000)
      :error -> nil
    end
  end

  # --- Artists ----------------------------------------------------------------

  @doc """
  Every album artist, with the albums credited to it, by name.
  """
  @spec artists([Album.t()]) :: [{Artist.t(), [Album.t()]}]
  def artists(albums) do
    albums
    |> Enum.flat_map(fn album -> Enum.map(album.artists, &{&1, album}) end)
    |> Enum.group_by(&elem(&1, 0).id)
    |> Enum.map(fn {_id, [{artist, _} | _] = pairs} ->
      {artist, Enum.map(pairs, &elem(&1, 1))}
    end)
    |> Enum.sort_by(fn {artist, _} -> {String.downcase(artist.name), artist.id} end)
  end

  # --- Search -------------------------------------------------------------------

  @doc """
  The res among `res_ids` carrying any name that contains `query`, ignoring
  case. Every name a res carries is searched, not only the one it is shown
  under (spec-01 §7.4).
  """
  @spec named_containing([Ecto.UUID.t()], String.t()) :: MapSet.t()
  def named_containing(res_ids, query) do
    pattern = "%" <> String.replace(query, ~r/([\\%_])/, "\\\\\\1") <> "%"

    MapSet.new(
      Repo.all(
        from n in Nomen,
          where: n.res_id in ^res_ids,
          where: ilike(n.nomen_string, ^pattern),
          distinct: true,
          select: n.res_id
      )
    )
  end

  # --- Companions ---------------------------------------------------------------

  @doc """
  The stored asset of the companion of a kind linked to a manifestation: the
  acquired original of the companion's digital item.
  """
  @spec companion(Ecto.UUID.t(), String.t()) :: Asset.t() | nil
  def companion(manifestation_id, kind) do
    Repo.one(
      from link in Association,
        join: d in DigitalItem,
        on: d.manifestation_id == link.subject_id,
        join: a in Asset,
        on: a.digital_item_id == d.id,
        join: r in AssetRole,
        on: r.asset_id == a.id and r.role_class == :acquired,
        where: link.refinement == ^Place.companion_link(kind),
        where: link.object_id == ^manifestation_id,
        where: link.subject_id not in subquery(recycled()),
        where: link.subject_id not in subquery(purged()),
        order_by: [desc: a.id],
        limit: 1,
        select: a
    )
  end

  defp recycled, do: from(b in RecycledRes, select: b.res_id)
  defp purged, do: from(t in Tombstone, select: t.res_id)
end
