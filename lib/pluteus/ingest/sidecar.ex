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
  file describes that file; any other describes what the directory holds. So a document's
  evidence reaches exactly what its link reaches, and the two cannot disagree about which
  holding they are about. One kind reaches further: a document that names the files it is
  about by path speaks for every directory beneath its own, and only for a file it names.

  **Read in the inbox**, where the file still lies. §4.3 moves a file out once the
  deployment takes it, and what it is has to be known before that; the directory is also
  where the relationship between a document and what it describes is plainest, since it is
  the arrangement a person made.

  The document is from the inbox, so it is hostile input: `Pluteus.Ingest.Document` reads
  it under spec-04 §11's bounds and nothing here parses markup itself.
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
  What the documents around a file in the inbox state about it.

  A document naming the file outranks one naming the directory, because the nearer
  statement about a thing is the one to believe.
  """
  @spec evidence(Path.t(), String.t()) :: evidence()
  def evidence(inbox, relative) do
    read =
      inbox
      |> documents(relative)
      |> Enum.map(fn {directory, name, at} -> stated(inbox, directory, name, at, relative) end)
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

  # Every metadata document in the file's own directory, and every one above it: the
  # latter speak only where they name the file, which `stated/4` decides.
  #
  # A document may already have been taken. A pass walks a directory in order and a
  # companion is decided by what it is, so the document beside a holding is often the
  # deployment's before the holding is examined; what it states does not stop being true
  # when its bytes move, so it is read where it now lies. The inbox copy answers where
  # both exist, since that is the one a person has been editing.
  defp documents(inbox, relative) do
    directories = above(Path.dirname(relative))

    in_inbox =
      for directory <- directories,
          name <- entries(Path.join(inbox, directory)),
          metadata?(Path.join([inbox, directory, name])),
          do: {directory, name, Path.join([inbox, directory, name])}

    taken =
      for taken <- taken_from(directories),
          not Enum.any?(in_inbox, fn {_at, name, _path} ->
            name == Path.basename(taken.inbox_path)
          end),
          do:
            {taken.inbox_directory, Path.basename(taken.inbox_path), Storage.path(taken.location)}

    in_inbox ++ taken
  end

  defp taken_from(directories) do
    Repo.all(
      from a in Acquisition,
        where: a.inbox_directory in ^directories,
        where: a.companion_kind == "metadata",
        where: not is_nil(a.inbox_released_at),
        order_by: a.id
    )
  end

  # The file's own directory and every directory it sits under, inside the inbox.
  defp above("."), do: ["."]
  defp above(directory), do: ["." | directory |> Path.split() |> Enum.scan(&Path.join(&2, &1))]

  defp entries(directory) do
    case File.ls(directory) do
      {:ok, names} -> Enum.sort(names)
      {:error, _unreadable} -> []
    end
  end

  defp metadata?(path) do
    File.regular?(path) and
      Registry.companion_kind(Path.basename(path), fn -> leading(path) end) == "metadata"
  end

  defp leading(path), do: Storage.leading_file(path, Registry.sidecar_ceiling())

  # What one document states about this file, or nil where it states nothing: a root the
  # registry does not name, bytes that are not markup, a document that could not be read
  # at all, or one above the file that does not name it.
  #
  # A document that cannot be read is not an error here — §6.3 is deciding a category from
  # whatever evidence there is, and a document nobody can parse is evidence of nothing.
  defp stated(inbox, directory, name, at, relative) do
    bytes = leading(at)

    case Registry.members_named_by(name) do
      nil -> as_markup(inbox, directory, name, relative, bytes)
      rule -> as_member(directory, relative, bytes, rule)
    end
  end

  # A document that names the files it is about by path states what it states only about
  # a file it names, wherever that file sits beneath it.
  defp as_member(directory, relative, bytes, rule) do
    read = Plexmatch.read(bytes)

    case Plexmatch.member_at(read, Path.relative_to(relative, directory)) do
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

  defp as_markup(inbox, directory, name, relative, bytes) do
    with true <- directory == Path.dirname(relative),
         rule when not is_nil(rule) <- Registry.sidecar_document(Registry.document_root(bytes)),
         {:ok, fields} <- Document.fields(bytes) do
      scope = scope(name, relative)

      %{scope: scope, category: categorizes(rule, scope, inbox, directory), fields: fields}
    else
      _states_nothing -> nil
    end
  end

  # A document about the file itself says what that file is. One about what the file
  # belongs to does not: an album document dates the release and never makes a track an
  # album.
  #
  # A document naming no file in particular says what a holding is only where the
  # directory holds one, which is the same condition §4.6 links an unnamed companion
  # under: among several it names none of them, and taking one would be a guess about
  # which.
  defp categorizes(%{describes: :whole}, _scope, _inbox, _directory), do: nil

  defp categorizes(%{describes: :holding, category: category}, :file, _inbox, _directory),
    do: category

  defp categorizes(%{describes: :holding, category: category}, :directory, inbox, directory),
    do: if(alone?(inbox, directory), do: category)

  # One file in the directory is a thing a document could be about. The rest are the
  # documents, the covers and the notes, which describe rather than are described.
  defp alone?(inbox, directory) do
    at = Path.join(inbox, directory)

    1 ==
      at
      |> entries()
      |> Enum.filter(&File.regular?(Path.join(at, &1)))
      |> Enum.count(&(Registry.companion_kind(&1, fn -> leading(Path.join(at, &1)) end) == nil))
  end

  defp scope(name, relative) do
    if base_name(name) == base_name(relative), do: :file, else: :directory
  end

  defp base_name(path),
    do: path |> Path.basename() |> Path.rootname() |> String.downcase()
end
