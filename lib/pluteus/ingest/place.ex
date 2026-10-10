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
  alias Pluteus.Catalog.Asset
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Refinements
  alias Pluteus.Catalog.Representative
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Ingest.Container
  alias Pluteus.Ingest.Credits
  alias Pluteus.Ingest.Cue
  alias Pluteus.Ingest.Finding
  alias Pluteus.Ingest.NarrationKey
  alias Pluteus.Ingest.Registry
  alias Pluteus.Ingest.ReleaseKey
  alias Pluteus.Ingest.SerialKey
  alias Pluteus.Ingest.Streams
  alias Pluteus.Ingest.TimeSpanKey
  alias Pluteus.Lifecycle
  alias Pluteus.PlatformEvents
  alias Pluteus.Presentation.Geometry
  alias Pluteus.Presentation.Orientation
  alias Pluteus.Principals
  alias Pluteus.Repo
  alias Pluteus.Storage

  @category_scheme "work-category"

  @doc """
  The scheme placement records work categories in.
  """
  @spec category_scheme() :: String.t()
  def category_scheme, do: @category_scheme

  @doc """
  The association refinement linking a companion of a kind to what it
  describes.

  A companion kind names its own relation — a cover art file is the cover art of
  what it depicts — so the refinement is the kind said as a relation rather than a
  second vocabulary beside it. The name is asserted against the registry (spec-01
  §6.3), so a kind the registry carries no refinement for raises here rather than
  reaching `Pluteus.Catalog.associate/3` with a name it will refuse.
  """
  @spec companion_link(String.t()) :: String.t()
  def companion_link(kind) do
    Refinements.name!(String.replace(kind, "_", "-") <> "-of")
  end

  @doc """
  One pass of the place stage: every identified acquisition with no uncleared
  finding at this stage whose inbox directory has settled, in the order they
  were acquired.

  Every such acquisition, deployment-wide. The inbox is read to answer whether a
  directory has settled and narrows nothing else, because `Pluteus.Ingest.inbox/0`
  is the only one there is and every acquisition arrived through it. Given a
  directory it does not hold, the inbox has nothing waiting in it, so the
  acquisitions from that directory are settled and are placed.
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
        contended_rows_in_order(acquisition)

        case place_by_class(acquisition) do
          :placed -> :placed
          {:finding, kind, detail} -> record_finding(acquisition, kind, detail)
        end
      end)

    link_companions(acquisition.inbox_directory)
    outcome
  end

  # Two placements running at once contend for the same few rows: the probe's tool
  # version, a grouping key, an artist key. Each waits for the other to commit, which is
  # what makes one release out of two tracks, and two that took them in different orders
  # would deadlock instead of queueing.
  #
  # The order every placement keeps is: the tool version, then the time-span key for the
  # date its container states, then its one grouping key — a release, a serial or a
  # narration — then the artist keys its credits name. `locked!/3` holds a placement to
  # it, taking the key's lock on the read, since an insert that conflicts locks nothing
  # and the row may already be there.
  #
  # The two that do not depend on the catalog are taken here, before anything is written.
  # The tool version comes first because a placement of a file carrying no streams would
  # otherwise never take it at all. The time-span key is second, and it has to be here
  # rather than where the date is recorded: a date is shared by every holding issued then,
  # so it is as contended as an artist is, and taking it after the artist keys put the two
  # in both orders across concurrent placements. That deadlocked.
  #
  # It is the whole transaction's order rather than one placement's. Several placements
  # inside one transaction hold what each of them took, so a later one asking for a row
  # in a different order than an earlier one is the same cycle.
  defp contended_rows_in_order(acquisition) do
    {:ok, _} = Annotations.record_tool_version("ffprobe", Streams.ffprobe_version())

    case issued_date(acquisition) do
      nil -> :ok
      date -> time_span_for(date)
    end

    :ok
  end

  # A grouping key, held for the rest of the transaction. The row is there either way: this
  # runs after an insert that either made it or found it.
  defp locked!(schema, field, key) do
    Repo.one!(from k in schema, where: field(k, ^field) == ^key, lock: "FOR UPDATE")
  end

  # §6.9. Two of the categories an audio holding can take are not tracks of a release. A
  # narration is a rendering of a text, so the text is the work and the reading is an
  # expression of it; a podcast episode is a work of its own within its serial. Anything
  # else was published as a track, which is what §6.4 places.
  defp place_by_class(%Acquisition{media_class: :audio} = acquisition) do
    case category_of(acquisition) do
      "audiobook" -> place_narration(acquisition)
      "podcast_episode" -> place_by_itself(acquisition)
      _published_as_a_track -> place_released(acquisition)
    end
  end

  defp place_by_class(%Acquisition{media_class: :video} = acquisition),
    do: place_container(acquisition)

  defp place_by_class(%Acquisition{} = acquisition), do: place_by_itself(acquisition)

  defp place_released(acquisition) do
    case cue_sheet_for(acquisition) do
      nil -> place_track(acquisition)
      cue -> place_cue_release(acquisition, cue)
    end
  end

  defp place_by_itself(%Acquisition{} = acquisition) do
    case serial_place(acquisition) do
      {:taken, detail} -> {:finding, "position_taken", detail}
      within -> place_alone_or_within(acquisition, within)
    end
  end

  defp place_alone_or_within(acquisition, within) do
    {:ok, %{work: work, expression: expression, manifestation: manifestation}} =
      Catalog.create_work(automatic(title(acquisition)))

    categorize(work.id, acquisition)
    credit(acquisition, work.id, expression.id)
    position_within(within, work.id, manifestation.id)
    represent(acquisition, work.id, [expression])
    carry(acquisition, manifestation.id)
  end

  # --- Audiobooks (§6.9) ------------------------------------------------------------

  # §6.9. A narration is a new rendering of the same material, so the work is the text and
  # the reading is an expression of it. The author is credited on the work and the narrator
  # on the expression, and the edition as published is the manifestation.
  #
  # The work is named by the book rather than by the file, because a file of a reading in
  # several parts is named for the chapter it holds and the work is the whole text.
  #
  # Several files are parts of one digital item: nothing was released as a track, so a
  # second file joins the reading the first made rather than becoming a holding beside it.
  defp place_narration(acquisition) do
    tags = embedded_tags(acquisition)
    book = Streams.first(tags, Registry.audiobook().titled_by) || title(acquisition)

    acquisition
    |> narration_for(book)
    |> carry_part(acquisition, tags)
  end

  # Joins the reading holding the key, or creates it, as `release_for/3` joins a release.
  defp narration_for(acquisition, book) do
    key = "narration:" <> String.downcase(String.trim(book))
    now = DateTime.utc_now()

    {inserted, _} =
      Repo.insert_all(NarrationKey, [%{key: key, inserted_at: now, updated_at: now}],
        on_conflict: :nothing,
        conflict_target: :key
      )

    existing = locked!(NarrationKey, :key, key)

    if inserted == 0 and live?(existing.narration_digital_item_id),
      do: %{
        manifestation_id: existing.narration_manifestation_id,
        digital_item_id: existing.narration_digital_item_id
      },
      else: create_narration(existing, acquisition, book)
  end

  defp create_narration(narration_key, acquisition, book) do
    {:ok, %{work: work, expression: expression, manifestation: manifestation}} =
      Catalog.create_work(automatic(book))

    categorize(work.id, acquisition)
    credit(acquisition, work.id, expression.id)
    represent(acquisition, work.id, [expression])

    {:ok, %{digital_item: digital_item}} =
      Catalog.create_digital_item(manifestation.id, automatic(book))

    narration_key
    |> Ecto.Changeset.change(
      narration_manifestation_id: manifestation.id,
      narration_digital_item_id: digital_item.id
    )
    |> Repo.update!()

    %{manifestation_id: manifestation.id, digital_item_id: digital_item.id}
  end

  # One part of a reading: an asset of the reading's digital item, at the sequence the file
  # states. A file stating none is placed after those that do, in arrival order, because a
  # reading has an order whether or not its files say so.
  defp carry_part(narration, acquisition, tags) do
    sequence =
      Streams.number(tags, Registry.audiobook().sequenced_by) ||
        next_part(narration.digital_item_id)

    {:ok, %{asset: _asset}} =
      Catalog.create_asset(
        narration.digital_item_id,
        %{
          id: acquisition.id,
          location: acquisition.location,
          measurement: acquisition.measurement,
          part_sequence: sequence,
          essence: acquisition.essence,
          verification_interval_seconds: verification_interval(acquisition.media_class),
          roles: [%{role_class: :acquired, role: "original"}]
        },
        automatic(Path.basename(acquisition.inbox_path))
      )

    record_probe(acquisition)

    # The part belongs to the reading before the reading is measured, because the sum is
    # taken over the parts the digital item holds and this is one of them.
    acquisition |> Acquisition.placed_changeset(narration.digital_item_id) |> Repo.update!()

    record_chapters(acquisition, narration, sequence)
    restate_extent(narration)
    record_issue_date(acquisition, narration.manifestation_id)
    record_analysis_source(narration.manifestation_id, narration.digital_item_id)

    {:ok, _event} =
      PlatformEvents.record("placed", {:res, narration.digital_item_id}, Actor.current())

    :placed
  end

  # §6.9. A chapter is a region of the reading rather than a holding of its own, so it is
  # a temporal address on the manifestation and nothing more: no work, no manifestation,
  # no digital item. The container states it, which is why nothing is derived here and a
  # container stating none produces none.
  #
  # A chapter's own times are relative to the file that declares them, and the address is
  # against the whole reading, so each is shifted past the parts that come before it. A
  # chapter at nought in part two is an hour into the reading, and recording it at nought
  # would put it in part one.
  defp record_chapters(acquisition, narration, sequence) do
    offset = parts_before(narration, sequence)

    for chapter <- Streams.chapters(acquisition.probe) do
      {:ok, %{address: address}} =
        Catalog.create_address(narration.manifestation_id, %{
          selector_type: :temporal,
          start_ms: chapter["start_ms"] + offset,
          end_ms: chapter["end_ms"] + offset
        })

      name_chapter(address.id, chapter["title"])
    end

    :ok
  end

  # A chapter the container titles is named by it. One it does not is a region with no name
  # of its own, which §6.3's composed name answers rather than a number invented here.
  defp name_chapter(_address_id, nil), do: :ok

  defp name_chapter(address_id, title) do
    {:ok, _} =
      Catalog.create_nomen(%{
        res_id: address_id,
        nomen_string: title,
        provenance: :automatic
      })

    :ok
  end

  # How much reading comes before a part: the stated duration of every part the reading
  # holds at a lower sequence. An asset carries the sequence and the acquisition carries
  # the probe that states the duration, and the two share an identifier.
  defp parts_before(narration, sequence) do
    Repo.all(
      from a in Acquisition,
        join: s in Asset,
        on: s.id == a.id,
        where: a.digital_item_id == ^narration.digital_item_id,
        where: s.part_sequence < ^sequence,
        select: a.probe
    )
    |> Enum.map(&stated_duration_ms/1)
    |> Enum.sum()
  end

  defp stated_duration_ms(probe) when is_map(probe) do
    case get_in(probe, ["format", "duration"]) do
      nil -> 0
      _stated -> Streams.duration_ms(probe)
    end
  end

  defp stated_duration_ms(_unprobed), do: 0

  defp next_part(digital_item_id) do
    sequences = for asset <- Catalog.assets_of(digital_item_id), do: asset.part_sequence || 0

    Enum.max([0 | sequences]) + 1
  end

  # §8.4. A reading's extent is the whole reading, so it is the sum of its parts and is
  # restated as each one joins. Recording one part's length as the whole's would make every
  # position a surface computes against it wrong.
  defp restate_extent(narration) do
    probes =
      Repo.all(
        from a in Acquisition,
          where: a.digital_item_id == ^narration.digital_item_id,
          select: a.probe
      )

    stated = probes |> Enum.map(&stated_duration_ms/1) |> Enum.sum()

    record_measured(narration.manifestation_id, measured(:millisecond, stated))
  end

  defp record_measured(_manifestation_id, nil), do: :ok

  defp record_measured(manifestation_id, {unit, magnitude}) do
    {:ok, _} = Addressing.record_extent(manifestation_id, unit, magnitude)
    :ok
  end

  # Who the holding credits, per the level the registry names. A category the registry
  # names nobody for credits nobody, which is every category but the two §6.9 reaches.
  defp credit(acquisition, work_id, expression_id) do
    case Registry.credits_of_category(category_of(acquisition)) do
      nil ->
        :ok

      per_level ->
        tags = embedded_tags(acquisition)
        separator = separator(acquisition)

        for {level, roles} <- per_level, {role, tag_names} <- roles do
          Credits.record(
            subject(level, work_id, expression_id),
            role,
            Credits.named_by(tags, tag_names, separator)
          )
        end

        :ok
    end
  end

  # Several names in one tag are separated the way the container separates them, so the
  # probe's own format name is what decides it (§6.4).
  defp separator(%Acquisition{probe: probe}) when is_map(probe),
    do: Registry.tag_separator(get_in(probe, ["format", "format_name"]))

  defp separator(%Acquisition{}), do: nil

  defp subject(:work, work_id, _expression_id), do: {:work, work_id}
  defp subject(:expression, _work_id, expression_id), do: {:expression, expression_id}

  # --- Serials (§6.9, spec-01 §5.4) -------------------------------------------------

  # §5.4 puts the two halves of a serial at different levels, and criterion 39 turns on
  # the second: the issue's work is connected to the serial's work by inspiration, and
  # where the issue sits is carried between their manifestations. The serial work has no
  # part, so nothing here writes one.
  defp position_within(nil, _work_id, _manifestation_id), do: :ok

  defp position_within(%{} = within, work_id, manifestation_id) do
    {:ok, _inspired} = Catalog.inspire(within.serial_work_id, work_id)

    {:ok, _part} =
      Catalog.add_manifestation_part(
        within.serial_manifestation_id,
        manifestation_id,
        within.position
      )

    :ok
  end

  # The serial is resolved before the issue's work exists, so that an issue whose number
  # the series already holds is a finding rather than a refused write part way through
  # placing it, which is how §6.4 answers the same collision between two tracks.
  defp serial_place(%Acquisition{} = acquisition) do
    case Registry.serial_of(category_of(acquisition)) do
      nil -> nil
      rule -> serial_place(acquisition, rule)
    end
  end

  defp serial_place(acquisition, rule) do
    tags = embedded_tags(acquisition)

    case Streams.first(tags, rule.named_by) do
      nil ->
        nil

      name ->
        serial = serial_for(rule, name)
        position = Streams.number(tags, rule.numbered_by)

        if taken?(serial.serial_manifestation_id, position) do
          {:taken, %{serial_manifestation_id: serial.serial_manifestation_id, position: position}}
        else
          Map.put(serial, :position, position)
        end
    end
  end

  # An issue the series does not number collides with nothing: a serial is ordered where
  # it says it is, and two issues stating no number are two parts of it all the same.
  defp taken?(_serial_manifestation_id, nil), do: false

  defp taken?(serial_manifestation_id, position),
    do: Enum.any?(Catalog.parts_of(serial_manifestation_id), &(&1.position == position))

  # Joins the serial holding the key, or creates it, the way `release_for/3` joins a
  # release. A key whose serial has since been recycled or purged no longer groups
  # anything, and a new serial takes it over.
  defp serial_for(rule, name) do
    key = "#{rule.category}:#{String.downcase(String.trim(name))}"
    now = DateTime.utc_now()

    {inserted, _} =
      Repo.insert_all(SerialKey, [%{key: key, inserted_at: now, updated_at: now}],
        on_conflict: :nothing,
        conflict_target: :key
      )

    existing = locked!(SerialKey, :key, key)

    if inserted == 0 and live?(existing.serial_manifestation_id),
      do: %{
        serial_work_id: existing.serial_work_id,
        serial_manifestation_id: existing.serial_manifestation_id
      },
      else: create_serial(existing, rule, name)
  end

  defp create_serial(serial_key, rule, name) do
    {:ok, %{work: work, manifestation: manifestation}} = Catalog.create_work(automatic(name))

    {:ok, _} = Catalog.categorize(work.id, @category_scheme, rule.category, :automatic)

    serial_key
    |> Ecto.Changeset.change(
      serial_work_id: work.id,
      serial_manifestation_id: manifestation.id
    )
    |> Repo.update!()

    %{serial_work_id: work.id, serial_manifestation_id: manifestation.id}
  end

  # spec-01 §6.5. What the bytes already read supply of the attributes this work's type
  # names, recorded on each expression and promoted to the work where it has one in one
  # manifestation. Categorization runs first, because the type is what says which attributes
  # are significant and a work with no category admits none.
  #
  # A key, a medium of performance and an intended audience are not in the bytes, so a
  # musical or textual work derives nothing here and §6.5 leaves those to be authored.
  defp represent(acquisition, work_id, expressions) do
    case derivable(acquisition, Representative.significant(work_id)) do
      empty when map_size(empty) == 0 ->
        :ok

      attributes ->
        for expression <- expressions do
          {:ok, _described} = Representative.describe(expression.id, attributes)
        end

        Representative.promote(work_id)
        :ok
    end
  end

  defp derivable(acquisition, significant) do
    %{}
    |> shape(acquisition, significant)
    |> turn(acquisition, significant)
  end

  defp shape(derived, acquisition, significant) do
    with true <- "aspect_ratio" in significant,
         {width, height} <- Streams.dimensions(acquisition.probe) do
      Map.put(derived, "aspect_ratio", Geometry.ratio(width, height))
    else
      _absent -> derived
    end
  end

  defp turn(derived, acquisition, significant) do
    with true <- "orientation" in significant,
         turn when not is_nil(turn) <- read_turn(acquisition) do
      Map.put(derived, "orientation", turn)
    else
      _absent -> derived
    end
  end

  defp read_turn(acquisition) do
    acquisition.location
    |> Storage.leading(Orientation.head_bytes())
    |> Orientation.of()
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
    record_issue_date(acquisition, manifestation_id)
    record_analysis_source(manifestation_id, digital_item.id)

    acquisition |> Acquisition.placed_changeset(digital_item.id) |> Repo.update!()

    # spec-01 §11.2's platform class: what happened to the holdings, which every
    # member sees. Recorded against the transaction's own principal, which is the
    # System principal for everything this module does (§3).
    {:ok, _event} = PlatformEvents.record("placed", {:res, digital_item.id}, Actor.current())

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

  # spec-01 §6.3's refinement of LRM-R35: when the edition in hand was issued, as the
  # container itself states it. It goes on the manifestation because it is a property of
  # the edition and not of the work — a reissue and a first pressing are one work and two
  # dates — and on the manifestation this holding is carried by, which is the one the
  # container is stating a date for.
  #
  # A container stating no date, or stating one in a form whose field order the form
  # itself does not fix, relates to no time-span. The date is then genuinely unexamined
  # rather than wrong, and [spec-10] §5.2 is what says so on a surface. Nothing here
  # consults the file's own timestamp, which spec-04 §4.5 forbids as evidence: it records
  # when the bytes were last written and a copy resets it.
  # The span itself was established before anything was written, where the order
  # placements keep puts it, so this reads the one that is already there.
  defp record_issue_date(acquisition, manifestation_id) do
    case issued_date(acquisition) do
      nil -> :ok
      date -> relate(manifestation_id, Repo.get!(TimeSpanKey, date).time_span_id)
    end
  end

  @doc """
  Records the date a placed holding's container states, for a holding placed before
  anything read one.

  The same reading, taken afterwards: the same tags, the same time-span and the same
  relation placement would have written. A holding whose container states no date it can
  read is left alone, because there is nothing to record and a file's own timestamp is
  not evidence of when anything was issued.
  """
  @spec record_date(Acquisition.t()) :: :recorded | :states_none
  def record_date(%Acquisition{state: :placed} = acquisition) do
    Actor.as(Principals.system!().id, fn ->
      case issued_date(acquisition) do
        nil ->
          :states_none

        date ->
          manifestation = Repo.get!(DigitalItem, acquisition.digital_item_id).manifestation_id

          relate(manifestation, time_span_for(date))

          :recorded
      end
    end)
  end

  @doc """
  Records how much of a placed holding there is, for one placed before anything measured
  it: the probe already on the acquisition, read the way placement reads it.

  A holding whose probe states no duration is left alone, and one already measured is
  left as it is, so this can be run after any ingest.
  """
  @spec record_extent(Acquisition.t()) :: :recorded | :measured_already | :states_none
  def record_extent(%Acquisition{state: :placed} = acquisition) do
    Actor.as(Principals.system!().id, fn ->
      manifestation = Repo.get!(DigitalItem, acquisition.digital_item_id).manifestation_id

      case extent_of(acquisition) do
        nil -> :states_none
        {unit, magnitude} -> measure(manifestation, unit, magnitude)
      end
    end)
  end

  defp measure(manifestation_id, unit, magnitude) do
    case Addressing.get_extent(manifestation_id, unit) do
      nil ->
        {:ok, _} = Addressing.record_extent(manifestation_id, unit, magnitude)
        :recorded

      _already ->
        :measured_already
    end
  end

  @doc """
  The date a holding's container states it was issued, or nil where it states none.
  """
  @spec issued_date(Acquisition.t()) :: String.t() | nil
  def issued_date(acquisition),
    do: Streams.date(embedded_tags(acquisition), Registry.issued_by())

  # A reading in several parts is one manifestation carrying an asset per part, so every
  # part states the same date about the same res and the relation is already there by the
  # second. The relation is the same fact however many files state it, so it is recorded
  # where it is absent rather than written again and refused.
  defp relate(manifestation_id, time_span_id) do
    refinement = Refinements.name!("time-of-publication-or-manufacture")

    unless time_span_id in Catalog.associated(manifestation_id, refinement) do
      {:ok, _} = Catalog.associate(manifestation_id, time_span_id, refinement)
    end

    :ok
  end

  # Joins the time-span holding the date, or creates it, as `release_for/4` joins a
  # release, and held for the rest of the transaction so two placements stating one date
  # queue on it rather than each making a span of its own.
  #
  # A span whose res has since been recycled or purged no longer dates anything, and a
  # new span takes the date over.
  defp time_span_for(date) do
    now = DateTime.utc_now()

    {inserted, _} =
      Repo.insert_all(TimeSpanKey, [%{key: date, inserted_at: now, updated_at: now}],
        on_conflict: :nothing,
        conflict_target: :key
      )

    existing = locked!(TimeSpanKey, :key, date)

    if inserted == 0 and live?(existing.time_span_id),
      do: existing.time_span_id,
      else: create_time_span(existing, date)
  end

  # The span is named by the date as stated, at the precision stated. A year is a year
  # and not a January, so nothing is filled out to make the name uniform.
  defp create_time_span(time_span_key, date) do
    {:ok, %{res: res}} = Catalog.create_named_res(:time_span, automatic(date))

    time_span_key |> Ecto.Changeset.change(time_span_id: res.id) |> Repo.update!()

    res.id
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

  # §12.1's page reader asks where a page sits in the whole, so a comic archive is measured
  # in pages. A page is an entry the archive holds: a release group's credit card carries no
  # mark distinguishing it from the last page, and counting the entries is what the archive
  # says rather than a guess about which of them is really a page.
  # Identification took the class from this container, so one reaching placement has
  # already been read once and reading it again cannot fail. Where it does, the bytes
  # changed underneath the acquisition, which is not a condition to record an extent around.
  #
  # The content is counted and the documents are not: a metadata document is not a page
  # (§6.9 criterion 35), and counting it would make a three-page comic four pages long.
  defp extent_of(%Acquisition{media_class: :package} = acquisition) do
    {:ok, %{content: content}} = Container.read(acquisition.location)

    measured(:page, length(content))
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
    tags = embedded_tags(acquisition)

    case release_key(acquisition, tags) do
      {:conflict, identifiers} ->
        {:finding, "evidence_names_two_releases", %{identifiers: identifiers}}

      {:ok, key} ->
        release =
          release_for(key, release_name(acquisition, tags), tags, separator(acquisition))

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

    Credits.record(
      {:work, work.id},
      :artist,
      Credits.from_tags(embedded_tags(acquisition), :artist, separator(acquisition))
    )

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
  defp release_for(key, name, tags, separator) do
    now = DateTime.utc_now()

    {inserted, _} =
      Repo.insert_all(ReleaseKey, [%{key: key, inserted_at: now, updated_at: now}],
        on_conflict: :nothing,
        conflict_target: :key
      )

    existing = locked!(ReleaseKey, :key, key)

    if inserted == 0 and live?(existing.release_manifestation_id),
      do: %{
        manifestation_id: existing.release_manifestation_id,
        expression_id: existing.release_expression_id
      },
      else: create_release(existing, name, tags, separator)
  end

  defp live?(nil), do: false
  defp live?(res_id), do: match?({:live, _}, Lifecycle.state(res_id))

  defp create_release(release_key, name, tags, separator) do
    {:ok, %{work: work, expression: expression, manifestation: manifestation}} =
      Catalog.create_work(automatic(name))

    Credits.record(
      {:work, work.id},
      :album_artist,
      Credits.from_tags(tags, :album_artist, separator)
    )

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
    tags = embedded_tags(acquisition)
    name = cue.title || release_name(acquisition, tags)

    release =
      release_for("single:" <> acquisition.id, name, tags, separator(acquisition))

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

    # The track's own length, which is what spec-01 §8.4's recorded figure is for. The
    # address says where in the release the track sits; it does not say how long the
    # track is to anything asking about the track, and §13.2's floor and ceiling and
    # every address against it are measured against the recorded figure.
    {:ok, _} = Addressing.record_extent(track.id, :millisecond, finish - cue_track.start_ms)
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

    {:ok, %{work: work, expression: expression, manifestation: manifestation}} =
      Catalog.create_work(automatic(expression_name(name, List.first(languages))))

    categorize(work.id, acquisition)

    parallel =
      for language <- Enum.drop(languages, 1) do
        {:ok, %{expression: parallel}} =
          Catalog.add_expression_embodied_in(
            work.id,
            manifestation.id,
            automatic(expression_name(name, language))
          )

        parallel
      end

    represent(acquisition, work.id, [expression | parallel])

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
    {:ok, _} = Catalog.categorize(work_id, @category_scheme, category_of(acquisition), :automatic)
  end

  # What §6.3 decides, without recording it. The serial an issue belongs to follows from
  # its category, and that has to be known before the issue's work is written.
  defp category_of(%Acquisition{} = acquisition),
    do: evidence(acquisition) || class_default(acquisition)

  # A companion's category is its kind (§4.6), which the name already established,
  # so there is nothing for a tag to decide.
  defp evidence(%Acquisition{media_class: :companion}), do: nil

  defp evidence(%Acquisition{} = acquisition) do
    Registry.category_from_tags(
      acquisition.media_class,
      embedded_tags(acquisition)
    )
  end

  # The tags a holding carries, from whichever reader answered them: a container with
  # streams states them in its own header, and a container of files states them in a
  # document the registry names inside it (§6.9 criterion 35). §6.3 weighs the two alike,
  # so nothing downstream asks which it was.
  defp embedded_tags(%Acquisition{} = acquisition),
    do: Map.merge(Streams.tags(acquisition.probe), acquisition.container_tags)

  defp class_default(%Acquisition{} = acquisition),
    do: Registry.default_category(acquisition.media_class, acquisition.companion_kind)

  defp title(acquisition) do
    Streams.first(embedded_tags(acquisition), ["title"]) ||
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
