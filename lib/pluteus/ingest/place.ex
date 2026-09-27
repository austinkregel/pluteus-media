defmodule Pluteus.Ingest.Place do
  @moduledoc """
  Places an identified acquisition in the catalog (spec-04 §6).

  A holding's work, expression, manifestation, digital item and asset are
  written in one transaction, with the asset taking the acquisition's
  identifier, and the same transaction records the placement on the
  acquisition. Every catalog write is the deployment's own and is attributed to
  the System principal.

  Every name and category placement writes carries automatic provenance, so a
  member's correction outranks it. Placement never renames anything it did not
  just create: a track joining a release adds nothing to the release's names.

  Placement acts on evidence and does not guess. Where the evidence is
  contradictory or a position is already taken, it records a finding and leaves
  the acquisition unplaced for a person.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Actor
  alias Pluteus.Annotations
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Addressing
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Ingest.Credits
  alias Pluteus.Ingest.Cue
  alias Pluteus.Ingest.Finding
  alias Pluteus.Ingest.Registry
  alias Pluteus.Ingest.ReleaseKey
  alias Pluteus.Ingest.Streams
  alias Pluteus.Lifecycle
  alias Pluteus.PlatformEvents
  alias Pluteus.Principals
  alias Pluteus.Repo
  alias Pluteus.Storage

  @category_scheme "work-category"

  @companion_links %{
    "cover_art" => "cover-art-of",
    "lyrics" => "lyrics-of",
    "subtitles" => "subtitles-of",
    "cue_sheet" => "cue-sheet-of",
    "description" => "description-of",
    "metadata" => "metadata-of"
  }

  @doc """
  The scheme placement records work categories in.
  """
  @spec category_scheme() :: String.t()
  def category_scheme, do: @category_scheme

  @doc """
  The association refinement linking a companion of a kind to what it
  describes.
  """
  @spec companion_link(String.t()) :: String.t()
  def companion_link(kind), do: Map.fetch!(@companion_links, kind)

  @doc """
  One pass of the place stage: every identified acquisition with no uncleared
  finding at this stage whose inbox directory has settled, in the order they
  were acquired.
  """
  @spec place_due(Path.t()) :: [{Ecto.UUID.t(), term()}]
  def place_due(inbox) do
    blocked =
      from f in Finding,
        where: f.stage == :place and is_nil(f.cleared_at),
        select: f.acquisition_id

    from(a in Acquisition,
      where: a.state == :identified,
      where: a.id not in subquery(blocked),
      order_by: a.id
    )
    |> Repo.all()
    |> Enum.filter(&directory_settled?(inbox, &1.inbox_directory))
    |> Enum.map(fn acquisition ->
      {acquisition.id,
       Ingest.isolated(:place, %{acquisition_id: acquisition.id}, fn -> place(acquisition) end)}
    end)
  end

  @doc """
  Whether nothing in an inbox directory is still arriving: no file there waits
  to be acquired, and no acquisition from it waits to be identified. A file
  whose identification failed is not waiting; it is a finding.
  """
  @spec directory_settled?(Path.t(), String.t()) :: boolean()
  def directory_settled?(inbox, directory) do
    pending_identification =
      from a in Acquisition,
        left_join: f in Finding,
        on: f.acquisition_id == a.id and f.stage == :identify and is_nil(f.cleared_at),
        where: a.inbox_directory == ^directory,
        where: a.state == :recorded or (a.state == :stored and is_nil(f.id))

    not Repo.exists?(pending_identification) and not waiting_in_inbox?(inbox, directory)
  end

  defp waiting_in_inbox?(inbox, directory) do
    case File.ls(Path.join(inbox, directory)) do
      {:ok, names} -> Enum.any?(names, &waiting?(inbox, directory, &1))
      {:error, :enoent} -> false
    end
  end

  defp waiting?(inbox, directory, name) do
    relative = if directory == ".", do: name, else: Path.join(directory, name)

    match?({:ok, %File.Stat{type: :regular}}, File.lstat(Path.join(inbox, relative))) and
      not Registry.ignored?(relative)
  end

  @doc """
  Places one identified acquisition. Placing one already placed changes
  nothing.
  """
  @spec place(Acquisition.t()) :: :placed | :finding | :already_placed
  def place(%Acquisition{state: :placed}), do: :already_placed

  # The bytes are read before the transaction opens, since reading a large file
  # takes as long as the file is large, and a transaction is not held open for
  # it. They must still be the bytes that were identified.
  def place(%Acquisition{state: :identified} = acquisition) do
    {:ok, measurement} = Catalog.measure(acquisition.location)

    if measurement.digest != acquisition.digest do
      raise "the bytes of #{acquisition.id} changed after they were identified"
    end

    acquisition = %{acquisition | measurement: measurement}

    outcome =
      Actor.as(Principals.system!().id, fn ->
        contended_rows_in_order()

        case place_by_class(acquisition) do
          :placed -> :placed
          {:finding, kind, detail} -> record_finding(acquisition, kind, detail)
        end
      end)

    link_companions(acquisition.inbox_directory)
    outcome
  end

  # Two placements running at once contend for the same few rows: the probe's
  # tool version, a release key, an artist key. Each waits for the other to
  # commit, which is what makes one release out of two tracks, but two
  # placements that took them in different orders would deadlock instead of
  # queueing. Every placement takes them in this one order, beginning with the
  # tool version, which a placement of a file carrying no streams would
  # otherwise never take at all.
  defp contended_rows_in_order do
    {:ok, _} = Annotations.record_tool_version("ffprobe", Streams.ffprobe_version())
    :ok
  end

  defp place_by_class(%Acquisition{media_class: :audio} = acquisition) do
    case cue_sheet_for(acquisition) do
      nil -> place_track(acquisition)
      cue -> place_cue_release(acquisition, cue)
    end
  end

  defp place_by_class(%Acquisition{media_class: :video} = acquisition),
    do: place_container(acquisition)

  defp place_by_class(%Acquisition{} = acquisition) do
    {:ok, %{work: work, manifestation: manifestation}} =
      Catalog.create_work(automatic(title(acquisition)))

    categorize(work.id, acquisition)
    carry(acquisition, manifestation.id)
  end

  # --- A holding's carrier ------------------------------------------------------

  # The digital item carrying a manifestation, its asset, the probe's reading of
  # it, the manifestation's analysis source, and the placement on the record.
  defp carry(acquisition, manifestation_id) do
    {:ok, %{digital_item: digital_item}} =
      Catalog.create_digital_item(manifestation_id, automatic(title(acquisition)))

    {:ok, %{asset: _asset}} =
      Catalog.create_asset(
        digital_item.id,
        %{
          id: acquisition.id,
          location: acquisition.location,
          measurement: acquisition.measurement,
          essence: acquisition.essence,
          verification_interval_seconds: verification_interval(acquisition.media_class),
          roles: [%{role_class: :acquired, role: "original"}]
        },
        automatic(Path.basename(acquisition.inbox_path))
      )

    record_probe(acquisition)
    record_extent(acquisition, manifestation_id)
    record_analysis_source(manifestation_id, digital_item.id)

    acquisition |> Acquisition.placed_changeset(digital_item.id) |> Repo.update!()

    # spec-01 §11.2's platform class: what happened to the holdings, which every
    # member sees. Recorded against the transaction's own principal, which is the
    # System principal for everything this module does (§3).
    {:ok, _event} = PlatformEvents.record("placed", digital_item.id, Actor.current())

    :placed
  end

  # §6.1. The probe's input is the asset whose bytes it read, which is the res
  # spec-02 §4.1 requires a derivation name. A digital item realized by parts has
  # an asset per part under one manifestation, and a probe recorded against the
  # manifestation would make each part's reading supersede the last.
  #
  # The asset takes the acquisition's identifier (§6.1), so the acquisition's own
  # identifier is the asset's.
  defp record_probe(%Acquisition{probe: nil}), do: :ok

  defp record_probe(acquisition) do
    {:ok, derivation} =
      Annotations.record_derivation(%{
        tool: "ffprobe",
        version: Streams.ffprobe_version(),
        input_id: acquisition.id,
        parameters: %{},
        derived_at: DateTime.utc_now()
      })

    {:ok, _} =
      Annotations.annotate(%{
        target_id: acquisition.id,
        body_type: "probe",
        body: acquisition.probe,
        derivation_id: derivation.id
      })

    :ok
  end

  # spec-01 §8.4. How much of the holding there is, in the unit its medium is
  # measured along. Every normalized position is a fraction of this figure, and
  # [spec-10] §13.2 weighs a reported position against it, so a holding without one
  # can carry an address but cannot say where in the whole that address sits.
  #
  # It goes on the manifestation, which is where the bytes are. An expression
  # embodied by two manifestations has two lengths, so the figure is not the
  # expression's to hold.
  defp record_extent(acquisition, manifestation_id) do
    case extent_of(acquisition) do
      nil ->
        :ok

      {unit, magnitude} ->
        {:ok, _} = Addressing.record_extent(manifestation_id, unit, magnitude)
        :ok
    end
  end

  # A sounding or moving holding is measured in time, which its container states.
  # A container that states no duration is a holding of unknown length: the figure
  # is recorded where it is known and never invented, and the absence surfaces
  # where a position is asked for rather than here.
  defp extent_of(%Acquisition{media_class: class, probe: probe})
       when class in [:audio, :video] and is_map(probe) do
    case get_in(probe, ["format", "duration"]) do
      nil -> nil
      _stated -> measured(:millisecond, Streams.duration_ms(probe))
    end
  end

  defp extent_of(%Acquisition{}), do: nil

  # §8.4's magnitude is how much there is, so nothing is not a quantity of it.
  defp measured(_unit, magnitude) when magnitude <= 0, do: nil
  defp measured(unit, magnitude), do: {unit, magnitude}

  defp record_analysis_source(manifestation_id, digital_item_id) do
    now = DateTime.utc_now()

    Repo.insert_all(
      "analysis_sources",
      [
        %{
          manifestation_id: Ecto.UUID.dump!(manifestation_id),
          digital_item_id: Ecto.UUID.dump!(digital_item_id),
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: :nothing,
      conflict_target: :manifestation_id
    )

    :ok
  end

  # --- Music (§6.4) ---------------------------------------------------------------

  defp place_track(acquisition) do
    tags = Streams.tags(acquisition.probe)

    case release_key(acquisition, tags) do
      {:conflict, identifiers} ->
        {:finding, "evidence_names_two_releases", %{identifiers: identifiers}}

      {:ok, key} ->
        release = release_for(key, release_name(acquisition, tags), tags)
        disc = Streams.number(tags, ["disc", "discnumber"]) || 1
        position = Streams.number(tags, ["track", "tracknumber"])
        medium = medium_for(release, disc, release_name(acquisition, tags))

        if position && Enum.any?(Catalog.parts_of(medium), &(&1.position == position)) do
          {:finding, "position_taken", %{disc: disc, track: position, release_key: key}}
        else
          place_track_in(acquisition, release, medium, position)
        end
    end
  end

  defp place_track_in(acquisition, release, medium, position) do
    {:ok, %{work: work, expression: recording, manifestation: track}} =
      Catalog.create_work(automatic(title(acquisition)))

    categorize(work.id, acquisition)
    Credits.record(work.id, :artist, Credits.from_tags(Streams.tags(acquisition.probe), :artist))
    {:ok, _} = Catalog.add_manifestation_part(medium, track.id, position)
    {:ok, _} = Catalog.aggregate(release.expression_id, recording.id)
    carry(acquisition, track.id)
  end

  @doc """
  The key a track's release is grouped by (§6.4), from the track's own
  evidence and nothing else.
  """
  @spec release_key(Acquisition.t(), map()) :: {:ok, String.t()} | {:conflict, [String.t()]}
  def release_key(acquisition, tags) do
    album = tags["album"]
    album_artist = Streams.first(tags, ["album_artist", "albumartist", "album artist"])

    case Streams.release_identifiers(tags) do
      [identifier] ->
        {:ok, "musicbrainz:" <> identifier}

      [_, _ | _] = identifiers ->
        {:conflict, identifiers}

      [] when is_binary(album) and is_binary(album_artist) ->
        evidence = [album, album_artist, tags["date"], Streams.disc_total(tags)]
        {:ok, "tags:" <> Jason.encode!(evidence)}

      [] ->
        {:ok, "single:" <> acquisition.id}
    end
  end

  # Joins the release holding the key, or creates it. The key row is written
  # first: a concurrent placement with the same key waits on it, and then finds
  # the release this one made. A key whose release has since been recycled or
  # purged no longer groups anything, and a new release takes it over.
  defp release_for(key, name, tags) do
    now = DateTime.utc_now()

    {inserted, _} =
      Repo.insert_all(ReleaseKey, [%{key: key, inserted_at: now, updated_at: now}],
        on_conflict: :nothing,
        conflict_target: :key
      )

    existing = Repo.get!(ReleaseKey, key)

    if inserted == 0 and live?(existing.release_manifestation_id),
      do: %{
        manifestation_id: existing.release_manifestation_id,
        expression_id: existing.release_expression_id
      },
      else: create_release(existing, name, tags)
  end

  defp live?(nil), do: false
  defp live?(res_id), do: match?({:live, _}, Lifecycle.state(res_id))

  defp create_release(release_key, name, tags) do
    {:ok, %{work: work, expression: expression, manifestation: manifestation}} =
      Catalog.create_work(automatic(name))

    Credits.record(work.id, :album_artist, Credits.from_tags(tags, :album_artist))

    {:ok, _} =
      Catalog.categorize(
        work.id,
        @category_scheme,
        Registry.default_category(:release, nil),
        :automatic
      )

    release_key
    |> Ecto.Changeset.change(
      release_manifestation_id: manifestation.id,
      release_expression_id: expression.id
    )
    |> Repo.update!()

    %{manifestation_id: manifestation.id, expression_id: expression.id}
  end

  defp medium_for(release, disc, name) do
    case Enum.find(Catalog.parts_of(release.manifestation_id), &(&1.position == disc)) do
      %{part_id: medium} ->
        medium

      nil ->
        {:ok, %{manifestation: medium}} =
          Catalog.add_manifestation(release.expression_id, automatic("#{name}, disc #{disc}"))

        {:ok, _} = Catalog.add_manifestation_part(release.manifestation_id, medium.id, disc)
        medium.id
    end
  end

  defp release_name(acquisition, tags), do: tags["album"] || title(acquisition)

  # --- A release in one file (§6.4) ------------------------------------------------

  defp cue_sheet_for(acquisition) do
    file_name = acquisition.inbox_path |> Path.basename() |> String.normalize(:nfc)

    from(a in Acquisition,
      where: a.inbox_directory == ^acquisition.inbox_directory,
      where: a.companion_kind == "cue_sheet",
      where: a.state in [:identified, :placed]
    )
    |> Repo.all()
    |> Enum.map(&Cue.parse(Storage.read(&1.location)))
    |> Enum.find(&(&1.file == file_name))
  end

  defp place_cue_release(acquisition, cue) do
    tags = Streams.tags(acquisition.probe)
    name = cue.title || release_name(acquisition, tags)
    release = release_for("single:" <> acquisition.id, name, tags)
    medium = medium_for(release, 1, name)
    duration_ms = Streams.duration_ms(acquisition.probe)

    cue.tracks
    |> Enum.with_index()
    |> Enum.each(fn {cue_track, index} ->
      finish = Enum.at(cue.tracks, index + 1, %{start_ms: duration_ms}).start_ms
      place_cue_track(release, medium, cue_track, finish)
    end)

    carry(acquisition, release.manifestation_id)
  end

  defp place_cue_track(release, medium, cue_track, finish) do
    {:ok, %{work: work, expression: recording, manifestation: track}} =
      Catalog.create_work(automatic(cue_track.title || "Track #{cue_track.number}"))

    {:ok, _} =
      Catalog.categorize(
        work.id,
        @category_scheme,
        Registry.default_category(:audio, nil),
        :automatic
      )

    {:ok, _} = Catalog.add_manifestation_part(medium, track.id, cue_track.number)
    {:ok, _} = Catalog.aggregate(release.expression_id, recording.id)

    {:ok, %{address: extent}} =
      Catalog.create_address(release.manifestation_id, %{
        selector_type: :temporal,
        start_ms: cue_track.start_ms,
        end_ms: finish
      })

    {:ok, _} = Catalog.associate(extent.id, track.id, "extent-of")
  end

  # --- Containers (§6.5) --------------------------------------------------------------

  defp place_container(acquisition) do
    name = title(acquisition)
    content = Enum.filter(acquisition.streams, & &1["content"])
    {commentary, main} = Enum.split_with(content, &("comment" in &1["disposition"]))

    languages =
      main
      |> Enum.filter(&(&1["kind"] in ["audio", "subtitle"]))
      |> Enum.map(& &1["language"])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    {:ok, %{work: work, manifestation: manifestation}} =
      Catalog.create_work(automatic(expression_name(name, List.first(languages))))

    categorize(work.id, acquisition)

    for language <- Enum.drop(languages, 1) do
      {:ok, _} =
        Catalog.add_expression_embodied_in(
          work.id,
          manifestation.id,
          automatic(expression_name(name, language))
        )
    end

    for stream <- commentary do
      {:ok, _} =
        Catalog.create_work_embodied_in(
          manifestation.id,
          automatic(expression_name("#{name}, commentary", stream["language"]))
        )
    end

    for selector <- Streams.track_selectors(content) do
      {:ok, _} = Catalog.create_address(manifestation.id, selector)
    end

    carry(acquisition, manifestation.id)
  end

  defp expression_name(name, nil), do: name
  defp expression_name(name, language), do: "#{name} (#{language})"

  # --- Companions (§4.6) ------------------------------------------------------------

  @doc """
  Links every placed companion in an inbox directory to what it describes.

  It waits until nothing from the directory remains to be placed, other than
  what a finding holds back, since until then the directory may yet produce a
  second release. Lyrics, a metadata sidecar and a subtitle named after a media
  file describe what was placed from that file; any other companion describes
  the release placed from the directory, and where the directory produced more
  than one, it is not linked and the ambiguity is a finding. A companion in a
  directory that produced no release describes nothing and is not linked.
  """
  @spec link_companions(String.t()) :: :ok
  def link_companions(directory) do
    if unplaced_in?(directory) do
      :ok
    else
      {companions, media} =
        directory |> placed_in() |> Enum.split_with(&(&1.media_class == :companion))

      Actor.as(Principals.system!().id, fn ->
        Enum.each(companions, &link_companion(&1, media))
      end)

      :ok
    end
  end

  defp unplaced_in?(directory) do
    Repo.exists?(
      from a in Acquisition,
        left_join: f in Finding,
        on: f.acquisition_id == a.id and f.stage in [:identify, :place] and is_nil(f.cleared_at),
        where: a.inbox_directory == ^directory,
        where: a.state in [:recorded, :stored, :identified] and is_nil(f.id)
    )
  end

  defp placed_in(directory) do
    Repo.all(
      from a in Acquisition,
        where: a.inbox_directory == ^directory and a.state == :placed,
        order_by: a.id
    )
  end

  defp link_companion(companion, media) do
    subject = manifestation_of(companion)
    refinement = companion_link(companion.companion_kind)

    unless Catalog.associated(subject, refinement) != [] do
      case described_by(companion, media) do
        {:ok, object} ->
          {:ok, _} = Catalog.associate(subject, object, refinement)

        :none ->
          :ok

        {:ambiguous, releases} ->
          record_finding_once(companion, "companion_describes_several_releases", %{
            releases: releases
          })
      end
    end
  end

  defp described_by(%Acquisition{companion_kind: "lyrics"} = lyrics, media),
    do: named_after(lyrics, media)

  # A metadata sidecar or a subtitle describes the file it is named after — a
  # player writes `film.xml` and `film.en.srt` beside `film.mkv` — and where it
  # is named after nothing, the release of its directory, as `.plexmatch` is.
  defp described_by(%Acquisition{companion_kind: kind} = companion, media)
       when kind in ["metadata", "subtitles"] do
    case named_after(companion, media) do
      :none -> describes_release(media)
      found -> found
    end
  end

  defp described_by(_companion, media), do: describes_release(media)

  defp named_after(companion, media) do
    base = base_name(companion.inbox_path)

    case Enum.find(media, &(base_name(&1.inbox_path) == base)) do
      nil -> named_under(base, media)
      holding -> {:ok, manifestation_of(holding)}
    end
  end

  # A companion may carry marks its media file does not: `film.en.forced.srt`
  # is the subtitle of `film.mkv`. The longest media name the companion's own
  # begins with is the one it was named after.
  defp named_under(base, media) do
    media
    |> Enum.filter(&String.starts_with?(base, base_name(&1.inbox_path) <> "."))
    |> Enum.max_by(&String.length(base_name(&1.inbox_path)), fn -> nil end)
    |> case do
      nil -> :none
      holding -> {:ok, manifestation_of(holding)}
    end
  end

  defp describes_release(media) do
    case media |> Enum.map(&(&1 |> manifestation_of() |> topmost())) |> Enum.uniq() do
      [] -> :none
      [release] -> {:ok, release}
      releases -> {:ambiguous, releases}
    end
  end

  defp topmost(manifestation_id) do
    case Catalog.wholes_of(manifestation_id) do
      [] -> manifestation_id
      [%{whole_id: whole} | _] -> topmost(whole)
    end
  end

  defp manifestation_of(acquisition),
    do: Repo.get!(DigitalItem, acquisition.digital_item_id).manifestation_id

  # Compared in normal form C: a lyrics file and its track are one name
  # whether a filesystem stored it composed or decomposed.
  defp base_name(inbox_path),
    do: inbox_path |> Path.basename() |> Path.rootname() |> String.normalize(:nfc)

  # --- Common -----------------------------------------------------------------------

  # §6.3 decides the category from evidence, and from the broad class only where
  # evidence decides nothing. The evidence read here is the file's own embedded
  # tags, which is what distinguishes an audiobook from a music recording: both
  # are one audio file of a text or a performance, and the bytes alone cannot say
  # which.
  defp categorize(work_id, acquisition) do
    value = evidence(acquisition) || class_default(acquisition)
    {:ok, _} = Catalog.categorize(work_id, @category_scheme, value, :automatic)
  end

  # A companion's category is its kind (§4.6), which the name already established,
  # so there is nothing for a tag to decide.
  defp evidence(%Acquisition{media_class: :companion}), do: nil

  defp evidence(%Acquisition{} = acquisition) do
    Registry.category_from_tags(
      acquisition.media_class,
      Streams.tags(acquisition.probe)
    )
  end

  defp class_default(%Acquisition{} = acquisition),
    do: Registry.default_category(acquisition.media_class, acquisition.companion_kind)

  defp title(acquisition) do
    Streams.first(Streams.tags(acquisition.probe), ["title"]) ||
      stem_or_file_name(acquisition.inbox_path)
  end

  # A dot file is all extension: `.plexmatch` has no stem, and a holding is
  # named under something rather than under nothing (spec-01 §6.1).
  defp stem_or_file_name(inbox_path) do
    case base_name(inbox_path) do
      "" -> inbox_path |> Path.basename() |> String.normalize(:nfc)
      stem -> stem
    end
  end

  defp automatic(name), do: %{nomen_string: name, provenance: :automatic}

  defp verification_interval(media_class) do
    :pluteus
    |> Application.fetch_env!(Ingest)
    |> Keyword.fetch!(:verification_interval_seconds)
    |> Map.fetch!(media_class)
  end

  defp record_finding(acquisition, kind, detail) do
    Ingest.record_finding(%{
      stage: :place,
      kind: kind,
      permanent: true,
      detail: detail,
      acquisition_id: acquisition.id
    })

    :finding
  end

  defp record_finding_once(acquisition, kind, detail) do
    open =
      from f in Finding,
        where: f.acquisition_id == ^acquisition.id and f.kind == ^kind and is_nil(f.cleared_at)

    unless Repo.exists?(open), do: record_finding(acquisition, kind, detail)
  end
end
