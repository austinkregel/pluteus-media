defmodule Pluteus.Ingest.Registry do
  @moduledoc """
  The vocabularies ingest decides by (spec-01 §17): names an inbox never
  acquires, companion patterns, codec and format essence, the containers that
  hold a still image, category defaults, and the standard format per broad
  class.

  They are seed data, not specification, and ship as a file under `priv` that a
  release replaces. The file is read once and held for the life of the node.
  """

  @key {__MODULE__, :registry}

  @doc """
  Whether a path relative to the inbox names something that is never a holding:
  operating-system metadata, a download still in progress, or anything inside a
  directory that holds only such things.
  """
  @spec ignored?(String.t()) :: boolean()
  def ignored?(relative_path) do
    %{"names" => names, "prefixes" => prefixes, "suffixes" => suffixes, "directories" => dirs} =
      registry()["inbox_ignore"]

    segments = Path.split(relative_path)
    {directories, [file_name]} = Enum.split(segments, -1)

    Enum.any?(directories, &(&1 in dirs)) or file_name in names or
      String.starts_with?(file_name, prefixes) or String.ends_with?(file_name, suffixes)
  end

  @doc """
  The companion kind a file name matches, or nil (spec-04 §4.6).

  A pattern matches by extension, optionally narrowed to a set of base names,
  or by the whole file name: a dot file such as `.plexmatch` has no extension
  to match on.

  A pattern naming root elements matches only a file whose markup begins with
  one of them, read from `leading`, which answers the file's first bytes. One
  extension carries more than one thing: `.nfo` is a media manager's metadata
  where its root says so, and a release's notes where it is not markup at all.

  A pattern may match by suffix, where an extension is not the whole of what names
  the file. A `.info.json` is two extensions and the second says nothing: the
  extension is `json` and the base name is whatever came before `.info`, so
  neither of the other two forms can express it.
  """
  @spec companion_kind(String.t(), (-> binary())) :: String.t() | nil
  def companion_kind(file_name, leading \\ fn -> "" end) do
    file_name = String.downcase(file_name)

    Enum.find_value(registry()["companions"], fn pattern ->
      if names?(pattern, file_name) and rooted?(pattern, leading), do: pattern["kind"]
    end)
  end

  @doc """
  Every companion kind a pattern can answer with.

  `companion_kind/2` returns one of these or nil, so this is the whole of what a
  companion may be. What each kind owes elsewhere — a category default, an association
  refinement — is checked against this list rather than against a copy of it.
  """
  @spec companion_kinds() :: [String.t()]
  def companion_kinds do
    registry()["companions"] |> Enum.map(& &1["kind"]) |> Enum.uniq() |> Enum.sort()
  end

  # A pattern names a file by its extension, narrowed to a set of base names where
  # it gives one; by a suffix, where the extension is not the whole of what names
  # it; or by the whole file name, for a dot file that has no extension to match.
  defp names?(pattern, file_name) do
    by_extension?(pattern, file_name) or
      String.ends_with?(file_name, pattern["suffixes"] || []) or
      file_name in (pattern["names"] || [])
  end

  defp by_extension?(pattern, file_name) do
    extension = file_name |> Path.extname() |> String.trim_leading(".")

    extension in (pattern["extensions"] || []) and
      (pattern["base_names"] == nil or Path.rootname(file_name) in pattern["base_names"])
  end

  defp rooted?(%{"roots" => roots}, leading), do: root_element(leading.()) in roots
  defp rooted?(_pattern, _leading), do: true

  # The first element of a document, without its namespace prefix. Text that is
  # not markup, and bytes that are not text, have no root element.
  defp root_element(bytes) when is_binary(bytes) do
    with true <- String.valid?(bytes),
         markup = String.replace(bytes, ~r/<!--.*?-->/s, ""),
         [_match, element] <- Regex.run(~r/<\s*([A-Za-z_][A-Za-z0-9_.:-]*)/, markup) do
      element |> String.downcase() |> String.split(":") |> List.last()
    else
      _unrooted -> nil
    end
  end

  @doc """
  The essence of one stream, from its codec and, for a codec with both modes,
  the probed parameter that tells them apart (spec-04 §5.2).
  """
  @spec stream_essence(map()) :: :lossy | :lossless | :unknown
  def stream_essence(%{"codec_name" => codec} = stream) do
    case Map.fetch(registry()["codecs"], codec) do
      {:ok, essence} when is_binary(essence) -> to_essence(essence)
      {:ok, %{"parameter" => parameter} = rule} -> by_parameter(rule, stream[parameter])
      :error -> by_prefix(codec)
    end
  end

  def stream_essence(_stream_without_codec), do: :unknown

  defp by_parameter(%{"cases" => cases} = rule, value) do
    case Map.fetch(cases, value) do
      {:ok, essence} -> to_essence(essence)
      :error when is_nil(value) -> :unknown
      :error -> rule |> Map.get("otherwise", "unknown") |> to_essence()
    end
  end

  defp by_prefix(codec) do
    Enum.find_value(registry()["codec_prefixes"], :unknown, fn {prefix, essence} ->
      if String.starts_with?(codec, prefix), do: to_essence(essence)
    end)
  end

  @doc """
  The class and essence of a format whose files carry no streams, or nil where
  the registry has no entry for it.
  """
  @spec streamless_format(String.t()) :: %{class: atom(), essence: atom()} | nil
  def streamless_format(format) do
    case registry()["streamless_formats"][format] do
      nil ->
        nil

      %{"class" => class, "essence" => essence} ->
        %{class: to_class(class), essence: to_essence(essence)}
    end
  end

  @doc """
  The class and essence an archive format takes where its entries corroborate it, or nil
  where the registry names no archive of that format.

  The class is conditional, which is why this is separate from `streamless_format/1`: the
  format is any ZIP or any RAR, so taking the class on the format alone would make every
  archive in the house a comic.
  """
  @spec archive_format(String.t()) :: %{class: atom(), essence: atom()} | nil
  def archive_format(format) do
    case registry()["archive_formats"][format] do
      nil ->
        nil

      %{"class" => class, "essence" => essence} ->
        %{class: to_class(class), essence: to_essence(essence)}
    end
  end

  @doc """
  Whether an archive entry is one a surface could render (spec-04 §5.3).

  Read by extension, which is what an archive's own listing gives without extracting every
  entry.
  """
  @spec renderable_entry?(String.t()) :: boolean()
  def renderable_entry?(name) do
    extension = name |> Path.extname() |> String.trim_leading(".") |> String.downcase()

    extension in registry()["renderable_entries"]["extensions"]
  end

  @doc """
  Whether an archive entry is worth opening to see if it is a metadata document
  (spec-04 §5.3).

  Decided from the listing alone, because deciding it from the root element means
  extracting the entry, and a comic holds two hundred pages that no root could name.
  """
  @spec container_candidate?(String.t()) :: boolean()
  def container_candidate?(name) do
    extension = name |> Path.extname() |> String.trim_leading(".") |> String.downcase()

    extension in registry()["container_documents"]["extensions"]
  end

  @doc """
  Whether these bytes are a metadata document the registry names, by their root element.

  The root element decides, as it does for a companion (`companion_kind/2`): it names a
  document a person renamed, and it refuses one that took the name and holds something
  else.
  """
  @spec container_document?(binary()) :: boolean()
  def container_document?(bytes) when is_binary(bytes),
    do: root_element(bytes) in registry()["container_documents"]["roots"]

  @doc """
  The most a metadata document inside a container may weigh (spec-04 §11).

  A document states a few fields about its container, so one longer than this is not a
  document that was written to be read and is refused rather than parsed.
  """
  @spec container_document_ceiling() :: pos_integer()
  def container_document_ceiling, do: registry()["container_documents"]["byte_ceiling"]

  @doc """
  How much of a file's head a deployment signature can need (spec-04 §5.1).

  One read of this length answers every signature, so a file PRONOM could not
  place costs one read rather than one per signature.
  """
  @spec signature_span() :: pos_integer()
  def signature_span do
    registry()["byte_signatures"]
    |> Enum.map(&(&1["offset"] + byte_size(bytes_of(&1))))
    |> Enum.max()
  end

  @doc """
  The format a deployment signature names for these bytes, or nil where none
  matches (spec-04 §5.1).

  A signature is a literal sequence at a stated offset in the file's own content:
  iNES names itself in the first four bytes, a Mega Drive dump at 0x100, an ISO 9660
  volume descriptor at 0x8001. The formats here are the ones PRONOM holds no byte
  signature for, or holds only an extension match for, which spec-03 §6 refuses.
  """
  @spec byte_signature(binary()) :: String.t() | nil
  def byte_signature(head) when is_binary(head) do
    Enum.find_value(registry()["byte_signatures"], fn signature ->
      expected = bytes_of(signature)
      offset = signature["offset"]

      if byte_size(head) >= offset + byte_size(expected) and
           binary_part(head, offset, byte_size(expected)) == expected do
        signature["format"]
      end
    end)
  end

  defp bytes_of(signature), do: Base.decode16!(signature["hex"], case: :lower)

  @doc """
  Whether a probed container holds a still image rather than moving pictures.
  """
  @spec image_container?(String.t() | nil) :: boolean()
  def image_container?(format_name), do: format_name in registry()["image_containers"]

  @doc """
  The category the file's own embedded tags name, or nil where they name none
  (spec-04 §6.3).

  A rule names one tag, the broad classes it may decide for, and a closed map from
  tag value to category. The value is matched **whole and case-folded**: `genre`
  reading `Audiobook` decides, and `Audiobooks & Spoken Word` does not. A substring
  match would make a genre of "Podcast Theme Music" a podcast episode, which is the
  guess §6.2's correction surface exists to avoid needing.

  A rule may instead decide on a tag being **there at all**, where carrying the field
  is itself the statement: a file that says which album it is a track of, and which
  track, is saying it is a track of an album. The rules are read in order, so one that
  reads a value decides before one that reads only presence.

  The classes are a guard on plausibility: an audiobook is audio, so a video file
  whose genre reads `Audiobook` is not placed as one.

  A miss is nil, and nothing stands in for it: §6.3 decides a category from evidence and
  from nothing else.
  """
  @spec category_from_tags(atom(), map()) :: String.t() | nil
  def category_from_tags(class, tags) do
    class = Atom.to_string(class)

    Enum.find_value(registry()["category_evidence"], fn rule ->
      if class in rule["classes"], do: decided_by(rule, tags)
    end)
  end

  defp decided_by(%{"values" => values, "tag" => tag}, tags), do: values[folded(tags[tag])]

  defp decided_by(%{"present" => category, "tag" => tag}, tags),
    do: if(stated?(tags[tag]), do: category)

  defp stated?(nil), do: false
  defp stated?(value), do: String.trim(value) != ""

  defp folded(nil), do: nil
  defp folded(value), do: value |> String.trim() |> String.downcase()

  @doc """
  The category a companion's kind is (spec-04 §4.6).

  A companion is the one holding whose category needs no evidence beyond itself: what it
  is was decided from the file, and a cover is cover art wherever it sits.
  """
  @spec companion_category(String.t()) :: String.t()
  def companion_category(companion_kind),
    do: Map.fetch!(registry()["categories"]["companion"], companion_kind)

  @doc """
  The category a release takes (spec-04 §6.4).

  A release is not a holding and has no bytes of its own: it is the work the tracks were
  released as, which placement writes, so what it is follows from having made one.
  """
  @spec release_category() :: String.t()
  def release_category, do: Map.fetch!(registry()["categories"], "release")

  @doc """
  The category a track of a release takes (spec-04 §6.4).

  A track read from a cue sheet is not a file and has no evidence of its own: what it is
  follows from the sheet, which describes a release and the tracks it was pressed with.
  """
  @spec track_category() :: String.t()
  def track_category, do: Map.fetch!(registry()["categories"], "audio")

  @doc """
  The category a format alone says a holding is, or nil (spec-04 §6.3).

  A format is evidence where it means one kind of thing: an EPUB is a book. It is not
  where a format carries anything — a FLAC is a recording or a reading and the bytes do
  not say which.
  """
  @spec category_from_format(String.t()) :: String.t() | nil
  def category_from_format(format) do
    case registry()["streamless_formats"][format] do
      nil -> nil
      rule -> rule["category"]
    end
  end

  @doc """
  The category a broad class says a holding is, or nil (spec-04 §6.3).

  A class decides only where it means one kind of thing. The three that mean several —
  video, audio and image — decide nothing, which is why a birthday, a film and an episode
  are told apart by what is stated about them and never by what their bytes are made of.
  """
  @spec category_from_class(atom()) :: String.t() | nil
  def category_from_class(class),
    do: registry()["class_evidence"]["of_class"][Atom.to_string(class)]

  @doc """
  The separator a container writes between several values in one tag, or nil where the
  registry names none for it and the field is taken whole (spec-04 §6.4, §6.9).

  Keyed by the format name the probe reports, because the convention is the container's:
  MP4 metadata separates names with a comma and ID3 with a semicolon, and reading one as
  the other either joins several people into a single credit or cuts a surname-first name
  in half.
  """
  @spec tag_separator(String.t() | nil) :: String.t() | nil
  def tag_separator(nil), do: nil
  def tag_separator(format_name), do: registry()["tag_separators"]["of_format"][format_name]

  @doc """
  Who a holding of this category credits, per level, or nil where the registry names none
  (spec-04 §6.9).

  The level is what the credit means rather than where it is stored: an author made the
  text and is credited on the work, a narrator made one reading of it and is credited on
  that expression.
  """
  @spec credits_of_category(String.t()) ::
          %{optional(:work | :expression) => %{String.t() => [String.t()]}} | nil
  def credits_of_category(category) do
    case registry()["credit_evidence"]["of_category"][category] do
      nil ->
        nil

      per_level ->
        Map.new(per_level, fn
          {"work", roles} -> {:work, roles}
          {"expression", roles} -> {:expression, roles}
        end)
    end
  end

  @doc """
  What names a reading and what orders its parts (spec-04 §6.9).
  """
  @spec audiobook() :: %{titled_by: [String.t()], sequenced_by: [String.t()]}
  def audiobook do
    %{"titled_by" => titled_by, "sequenced_by" => sequenced_by} = registry()["audiobooks"]

    %{titled_by: titled_by, sequenced_by: sequenced_by}
  end

  @doc """
  The tags that state when a manifestation was issued, in the order they are read
  (spec-01 §6.3, §6.4).
  """
  @spec issued_by() :: [String.t()]
  def issued_by, do: registry()["dates"]["issued_by"]

  @doc """
  Every category placement can record (spec-04 §6.3, §6.9).

  Three sources reach the category scheme: the default for a broad class or a companion
  kind, a value the file's own tags decide, and the category a serial work takes. Each
  reaches the same scheme, so each is a category the rest of the deployment must know.
  """
  @spec recordable_categories() :: [String.t()]
  def recordable_categories do
    defaults =
      registry()["categories"]
      |> Map.values()
      |> Enum.flat_map(fn
        category when is_binary(category) -> [category]
        per_kind when is_map(per_kind) -> Map.values(per_kind)
      end)

    tagged = Enum.flat_map(registry()["category_evidence"], &stated_by/1)
    filed = for {_segment, rule} <- of_segment(), do: rule["category"]
    beside = for {_root, rule} <- of_root(), rule["category"], do: rule["category"]
    named = for {_name, rule} <- names_members(), do: rule["category"]

    from_format =
      for {_format, rule} <- registry()["streamless_formats"],
          rule["category"],
          do: rule["category"]

    from_class = Map.values(registry()["class_evidence"]["of_class"])

    (defaults ++
       tagged ++
       serial_categories() ++ filed ++ beside ++ named ++ from_format ++ from_class)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  What the path a holding arrived at states about it, or nil where it states nothing
  (spec-04 §6.3).

  Segments are compared whole and case-folded, so a directory called `TV` decides and one
  called `TV Rips` does not, and the first segment the registry names is the one that
  answers: a holding filed under `TV/…` was put under television by whoever filed it, and
  a deeper directory is how they arranged it rather than a second statement.

  The answer carries the category and the serial the path names where the rule says a
  segment names one. A path numbers nothing: a file name beginning with digits is not a
  season and an episode, and reading one as the other would order a series by a convention
  nobody stated. A rule that applies to other classes than this holding's states nothing
  about it.
  """
  @spec path_evidence(String.t(), atom()) ::
          %{category: String.t(), serial_name: String.t() | nil} | nil
  def path_evidence(inbox_path, media_class) do
    directories = inbox_path |> Path.split() |> Enum.drop(-1)

    case filed_under(directories, media_class) do
      nil -> nil
      {index, rule} -> stated(rule, directories, index)
    end
  end

  defp of_segment, do: registry()["path_evidence"]["of_segment"]
  defp of_root, do: registry()["sidecar_documents"]["of_root"]
  defp names_members, do: registry()["sidecar_documents"]["names_members"]

  # A rule reads a tag's value, or reads the tag being there at all.
  defp stated_by(%{"values" => values}), do: Map.values(values)
  defp stated_by(%{"present" => category}), do: [category]

  defp filed_under(directories, media_class) do
    directories
    |> Enum.with_index()
    |> Enum.find_value(fn {segment, index} ->
      rule = of_segment()[String.downcase(segment)]

      if rule && Atom.to_string(media_class) in Map.fetch!(rule, "classes"), do: {index, rule}
    end)
  end

  defp stated(rule, directories, index) do
    %{
      category: Map.fetch!(rule, "category"),
      serial_name: serial_name(rule, directories, index)
    }
  end

  defp serial_name(%{"serial_named_by_segment" => further}, directories, index),
    do: Enum.at(directories, index + further)

  defp serial_name(_naming_none, _directories, _index), do: nil

  @doc """
  The serial a holding of this category is an issue of, or nil where the category belongs
  to no serial (spec-04 §6.9, spec-01 §5.4).

  The rule carries the serial's own category, the tags that may name it, and the tags that
  may number the issue within it. A category the registry does not list here is placed on
  its own, which is every category but one until a podcast can be recognized.
  """
  @spec serial_of(String.t()) ::
          %{
            category: String.t(),
            named_by: [String.t()],
            numbered_by: [String.t()],
            seasoned_by: [String.t()],
            episodes_per_season: pos_integer() | nil
          }
          | nil
  def serial_of(category) do
    case registry()["serials"]["of_category"][category] do
      nil ->
        nil

      %{"category" => serial, "named_by" => named_by, "numbered_by" => numbered_by} = rule ->
        %{
          category: serial,
          named_by: named_by,
          numbered_by: numbered_by,
          seasoned_by: rule["seasoned_by"] || [],
          episodes_per_season: rule["episodes_per_season"]
        }
    end
  end

  @doc """
  What a metadata document with this root element is about, or nil where the registry
  names no such root (spec-04 §6.3).

  `describes` is `:holding` where the document is about the file itself, and the category
  it states is that file's; `:whole` where it is about what the file belongs to, so an
  album document dates the release and never makes a track an album.

  A root a format writes for more than one kind of thing says which by the fields it
  carries, and the rule names them: a document carrying none of them states what the
  holding is called rather than what it is, and decides no category.
  """
  @spec sidecar_document(String.t() | nil, map()) ::
          %{describes: :holding | :whole, category: String.t() | nil} | nil
  def sidecar_document(root, fields \\ %{})

  def sidecar_document(nil, _fields), do: nil

  def sidecar_document(root, fields) do
    case registry()["sidecar_documents"]["of_root"][root] do
      nil ->
        nil

      rule ->
        %{describes: describes(rule["describes"]), category: decides(rule, fields)}
    end
  end

  # A rule naming the fields it decides on decides only where the document carries one.
  defp decides(%{"when" => named} = rule, fields) do
    if Enum.any?(named, &Map.has_key?(fields, &1)), do: rule["category"]
  end

  defp decides(rule, _fields), do: rule["category"]

  defp describes("holding"), do: :holding
  defp describes("whole"), do: :whole

  @doc """
  The root element a document begins with, without its namespace prefix, or nil where
  the bytes are not markup.
  """
  @spec document_root(binary()) :: String.t() | nil
  def document_root(bytes), do: root_element(bytes)

  @doc """
  How much of a sidecar document is read. A document past this is refused rather than
  parsed, as a document inside a container is.
  """
  @spec sidecar_ceiling() :: pos_integer()
  def sidecar_ceiling, do: registry()["sidecar_documents"]["byte_ceiling"]

  @doc """
  The rule for a document that names the files it is about by path, or nil.

  Such a document speaks for every directory beneath its own, which no other document
  does. Its fields are read under the names the rest of this registry uses, because what
  it states is about the whole and not about any one file.
  """
  @spec members_named_by(String.t()) ::
          %{category: String.t(), fields_as: %{String.t() => String.t()}} | nil
  def members_named_by(file_name) do
    case registry()["sidecar_documents"]["names_members"][String.downcase(file_name)] do
      nil -> nil
      rule -> %{category: rule["category"], fields_as: rule["fields_as"]}
    end
  end

  @doc """
  Every category that is a serial work rather than an issue of one (spec-01 §5.4).

  A serial arranges its issues on its own manifestation, so the parts of that
  manifestation are the serial's members. Every other whole arranges something else:
  a release arranges the media it was pressed on, and those are not its tracks.
  """
  @spec serial_categories() :: [String.t()]
  def serial_categories do
    for {_issue, rule} <- registry()["serials"]["of_category"], do: rule["category"]
  end

  @doc """
  The media type a format is served as, or `application/octet-stream` where the
  registry maps none (spec-07 §4.4).
  """
  @spec media_type(String.t()) :: String.t()
  def media_type(format),
    do: Map.get(registry()["media_types"], format, "application/octet-stream")

  @doc """
  What a household calls the format, for a surface telling two holdings of one name
  apart.

  Keyed through `media_type/1`, so the four PRONOM identifications of a PDF are one
  word. A media type the registry holds no word for raises rather than reaching a person
  as itself: a row saying `application/epub+zip` is the model's vocabulary on a surface,
  which §8.5 forbids.
  """
  @spec format_name(String.t()) :: String.t()
  def format_name(format), do: name_of_media_type(media_type(format))

  @doc """
  What a household calls what is served under a media type.

  A surface saying what it handed a client knows the media type it set, not the format
  that was identified: those are the bytes' own fact and what was sent is the deployment's
  statement about them.
  """
  @spec name_of_media_type(String.t()) :: String.t()
  def name_of_media_type(media_type) do
    registry()
    |> Map.fetch!("format_names")
    |> Map.fetch!("of_media_type")
    |> Map.fetch!(media_type)
  end

  @doc """
  The standard format a broad class is normalized into, or nil where the
  registry names none and a lossless acquisition is adopted as its own master.
  """
  @spec standard_format(atom()) :: map() | nil
  def standard_format(class), do: registry()["standard_formats"][Atom.to_string(class)]

  # The essences and classes the registry may name, mapped to the atoms they mean.
  #
  # Written out rather than converted, because an atom exists only once some module
  # carrying it as a literal has been loaded, and that is a property of the whole VM's
  # load history rather than of this call. Converting here would make a value the registry
  # should not hold and a module that happens not to be loaded yet raise the same error,
  # naming neither the registry nor the key.
  #
  # Held as literals here, the atoms exist whenever this module does, and a value outside
  # the map raises `KeyError` naming the value — which is what a registry saying something
  # the code does not admit should look like.
  @essences %{
    "lossy" => :lossy,
    "lossless" => :lossless,
    "unknown" => :unknown,
    "not_applicable" => :not_applicable
  }

  @classes %{
    "companion" => :companion,
    "audio" => :audio,
    "video" => :video,
    "image" => :image,
    "text" => :text,
    "package" => :package,
    "software" => :software
  }

  @doc """
  The essences and classes this registry admits, which the schema's own vocabularies are
  asserted against.
  """
  @spec vocabularies() :: %{essences: [atom()], classes: [atom()]}
  def vocabularies,
    do: %{essences: Map.values(@essences), classes: Map.values(@classes)}

  defp to_essence(essence), do: Map.fetch!(@essences, essence)

  defp to_class(class), do: Map.fetch!(@classes, class)

  defp registry do
    case :persistent_term.get(@key, nil) do
      nil ->
        loaded =
          :pluteus
          |> :code.priv_dir()
          |> Path.join("registries/ingest.json")
          |> File.read!()
          |> Jason.decode!()

        :persistent_term.put(@key, loaded)
        loaded

      loaded ->
        loaded
    end
  end
end
