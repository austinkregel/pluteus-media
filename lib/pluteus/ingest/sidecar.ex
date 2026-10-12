defmodule Pluteus.Ingest.Sidecar do
  @moduledoc """
  What a metadata document beside a holding states about it (spec-04 §6.3, §4.6).

  §6.3 names a companion `.nfo` among the evidence a category is decided from, and for a
  great deal of what a household holds it is the only thing that says what a file is: a
  television rip states nothing in its own container — no title, no show, no number — and
  the document a media manager wrote beside it states all three.

  **The root element says what the document is about**, which is already how §4.6 tells a
  media manager's `.nfo` from a release's notes. The registry holds that vocabulary and
  what each root describes; a root it does not name states nothing, rather than being read
  as whatever it resembles.

  **Scope follows the rule §4.6 links a companion by.** A document named after a media
  file describes that file; any other describes what was placed from the directory. So a
  document's evidence reaches exactly what its link reaches, and the two cannot disagree
  about which holding they are about.

  The document is from the inbox, so it is hostile input: `Pluteus.Ingest.Document` reads
  it under spec-04 §11's bounds and nothing here parses anything itself.
  """

  import Ecto.Query, only: [from: 2]

  alias Pluteus.Ingest.Acquisition
  alias Pluteus.Ingest.Document
  alias Pluteus.Ingest.Plexmatch
  alias Pluteus.Ingest.Registry
  alias Pluteus.Repo
  alias Pluteus.Storage

  @typedoc """
  What the documents beside a holding state: the category one of them says it is, and
  the fields all of them carry, under the names they were written with.
  """
  @type evidence :: %{category: String.t() | nil, fields: %{String.t() => String.t()}}

  @doc """
  What the documents in a holding's own inbox directory state about it.

  A document naming this file outranks one naming the directory, because the more
  specific statement about a thing is the one to believe; neither outranks what the
  file's own container says about itself, which is the holding speaking rather than a
  record someone kept about it.
  """
  @spec evidence(Acquisition.t()) :: evidence()
  def evidence(%Acquisition{} = acquisition) do
    read =
      acquisition
      |> documents()
      |> Enum.map(&stated(&1, acquisition))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(&nearness/1)

    %{
      category: Enum.find_value(read, & &1.category),
      fields: Enum.reduce(read, %{}, fn one, carried -> Map.merge(one.fields, carried) end)
    }
  end

  # The nearer statement about a thing is the one to believe, so a document named after
  # the file is read before one that names the directory, and what the nearer one says is
  # what survives the merge.
  defp nearness(%{scope: :file}), do: 0
  defp nearness(%{scope: :directory}), do: 1

  @doc """
  Whether a holding is one a document beside it could be about.

  A document is not: a sidecar describing a sidecar is not a thing media managers write,
  and reading one would let a release's notes name the category of the notes beside it.
  """
  @spec subject?(Acquisition.t()) :: boolean()
  def subject?(%Acquisition{media_class: :companion}), do: false
  def subject?(%Acquisition{}), do: true

  # Every metadata companion that could be about this holding: one in its own directory,
  # which is what §4.6 scopes a companion by, and one above it that names the files it is
  # about by path, which is the only kind that reaches past its own directory. §8's gate
  # means everything in a directory has been identified before anything in it is placed.
  defp documents(%Acquisition{} = acquisition) do
    Repo.all(
      from a in Acquisition,
        where: a.inbox_directory in ^above(acquisition.inbox_directory),
        where: a.companion_kind == "metadata",
        where: a.state in [:identified, :placed],
        order_by: a.id
    )
  end

  # The holding's own directory and every directory it sits under, inside the inbox.
  defp above(directory), do: directory |> Path.split() |> Enum.scan(&Path.join(&2, &1))

  # What one document states about this holding, or nil where it states nothing: a root
  # the registry does not name, bytes that are not markup, a document that could not be
  # read at all, or one that sits above the holding and does not name it.
  #
  # A document that cannot be read is not an error here — §6.3 is deciding a category from
  # whatever evidence there is, and a document nobody can parse is evidence of nothing.
  defp stated(%Acquisition{} = document, %Acquisition{} = subject) do
    bytes = Storage.leading(document.location, Registry.sidecar_ceiling())

    case Registry.members_named_by(Path.basename(document.inbox_path)) do
      nil -> as_markup(document, subject, bytes)
      rule -> as_member(document, subject, bytes, rule)
    end
  end

  # A document that names the files it is about by path states what it states only about
  # a file it names, wherever that file sits beneath it.
  defp as_member(document, subject, bytes, rule) do
    read = Plexmatch.read(bytes)
    relative = Path.relative_to(subject.inbox_path, document.inbox_directory)

    case Plexmatch.member_at(read, relative) do
      nil ->
        nil

      member ->
        %{
          scope: :file,
          category: rule.category,
          fields: read.fields |> renamed(rule.fields_as) |> Map.merge(numbered(member))
        }
    end
  end

  # Only the fields the rule names, under the names the rest of the registry uses: a
  # match file's `Title` is the show's and never the episode's.
  defp renamed(fields, as) do
    for {from, to} <- as, value = fields[from], into: %{}, do: {to, value}
  end

  defp numbered(%{season: season, episode: nil}), do: %{"season" => to_string(season)}

  defp numbered(%{season: season, episode: episode}),
    do: %{"season" => to_string(season), "episode" => to_string(episode)}

  defp as_markup(document, subject, bytes) do
    with true <- document.inbox_directory == subject.inbox_directory,
         rule when not is_nil(rule) <- Registry.sidecar_document(Registry.document_root(bytes)),
         {:ok, fields} <- Document.fields(bytes) do
      scope = scope(document, subject)

      %{scope: scope, category: categorizes(rule, scope, subject), fields: fields}
    else
      _states_nothing -> nil
    end
  end

  # A document about the file itself says what that file is. One about what the file
  # belongs to does not: an album document dates the release and never makes a track an
  # album.
  #
  # A document naming no file in particular says what the holding is only where the
  # directory produced one, which is the same condition §4.6 links an unnamed companion
  # under: among several it names none of them, and taking one would be a guess about
  # which.
  defp categorizes(%{describes: :whole}, _scope, _subject), do: nil
  defp categorizes(%{describes: :holding, category: category}, :file, _subject), do: category

  defp categorizes(%{describes: :holding, category: category}, :directory, subject),
    do: if(alone?(subject), do: category)

  defp alone?(%Acquisition{} = subject) do
    1 ==
      Repo.aggregate(
        from(a in Acquisition,
          where: a.inbox_directory == ^subject.inbox_directory,
          where: a.media_class != :companion
        ),
        :count
      )
  end

  # A document named after the file describes that file; any other describes what was
  # placed from the directory, which is §4.6's own rule.
  defp scope(document, subject) do
    if base_name(document.inbox_path) == base_name(subject.inbox_path),
      do: :file,
      else: :directory
  end

  defp base_name(inbox_path),
    do: inbox_path |> Path.basename() |> Path.rootname() |> String.downcase()
end
