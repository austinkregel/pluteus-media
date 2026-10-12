defmodule Pluteus.Publication do
  @moduledoc """
  An EPUB's text, in the order the publication reads in ([spec-10] §11.5, §12.1).

  A publication of this kind is an archive of documents plus a package document saying
  which of them are the publication and in what order. So reading one is three reads:
  the container, which names the package; the package, whose spine is the reading order;
  and each document the spine names.

  The divisions are the spine's own documents. §20 holds no page length for text, and the
  publication is already divided by whoever made it — a document each for the cover, the
  foreword, each chapter — so a reader stepping through them steps through the book's own
  parts rather than through a length this deployment chose.

  **Every document is somebody else's XML**, so `Pluteus.Xml` governs each parse: nothing
  a document names is opened, an entity is not expanded into more than it is, and each
  read is bounded in bytes and in time. A document that is not well-formed is refused
  naming the entry rather than contributing whatever parsed before the error, because
  half a chapter read as the whole of it is a book with a hole in it that nothing says is
  there.
  """

  alias Pluteus.Archive
  alias Pluteus.Storage
  alias Pluteus.Xml

  # EPUB requires the `mimetype` entry be first in the archive and stored uncompressed, so
  # what it says is readable from the archive's head alone. Where its content begins is the
  # entry's own header's answer rather than a fixed offset: the header is 30 bytes and then
  # states how long the name and the extra field after it are, and a writer that emits an
  # extra field would move everything after it.
  @signature "application/epub+zip"
  @name "mimetype"

  # Far more than the 38 bytes a header and that name take, so an extra field no writer
  # has yet emitted does not read as a publication that is not one.
  @head 1_024

  @container "META-INF/container.xml"

  # A container or a package document states structure and is small; a document of the
  # publication is prose and is not. Neither is an image, which is why neither ceiling is
  # the archive's own.
  @structure 2_000_000
  @content 16_000_000

  @typedoc """
  Why a publication could not be read: the archive would not open, the entry a document
  named is not in it, or a document would not parse — each naming what it was reading.
  """
  @type refusal :: {:no_entry, String.t()} | {:unreadable, String.t(), term()}

  @doc """
  Whether the bytes at a location are a publication of this kind.

  Read from the archive's own head rather than from the name, which spec-04 §4.5 forbids
  consulting: the container states what it is in a fixed place and that statement is the
  evidence.
  """
  @spec publication?(String.t()) :: boolean()
  def publication?(location) do
    case Storage.leading(location, @head) do
      <<"PK", 3, 4, _fixed::binary-size(22), named::little-16, extra::little-16, head::binary>> ->
        says_so?(head, named, extra)

      _not_an_archive ->
        false
    end
  end

  defp says_so?(head, named, extra) do
    with <<name::binary-size(named), _extra::binary-size(extra), stated::binary>> <- head,
         @name <- name,
         true <- byte_size(stated) >= byte_size(@signature) do
      binary_slice(stated, 0, byte_size(@signature)) == @signature
    else
      _another_archive -> false
    end
  end

  @doc """
  The publication's documents, in reading order, as text.
  """
  @spec divisions(String.t()) :: {:ok, [String.t()]} | {:error, refusal()}
  def divisions(location) do
    with {:ok, package} <- package(location),
         {:ok, entries} <- spine(location, package) do
      read_each(location, entries)
    end
  end

  # The container names the package document and nothing else is read from it. A
  # publication may declare several renditions; the first is the one it opens with.
  defp package(location) do
    with {:ok, bytes} <- entry(location, @container, @structure),
         {:ok, named} <- parse(bytes, @container, &rootfile/3, []) do
      case Enum.reverse(named) do
        [path | _other_renditions] -> {:ok, path}
        [] -> {:error, {:unreadable, @container, :names_no_package}}
      end
    end
  end

  defp spine(location, package) do
    with {:ok, bytes} <- entry(location, package, @structure),
         {:ok, read} <- parse(bytes, package, &package_of/3, %{items: %{}, spine: []}) do
      ordered(read, package)
    end
  end

  # The spine names items by identifier and the manifest says where each one is, so an
  # identifier the manifest does not carry names nothing — which is the publication
  # contradicting itself rather than a document that is merely absent.
  defp ordered(%{items: items, spine: spine}, package) do
    Enum.reduce_while(Enum.reverse(spine), {:ok, []}, fn id, {:ok, so_far} ->
      case Map.fetch(items, id) do
        {:ok, href} -> {:cont, {:ok, [beside(package, href) | so_far]}}
        :error -> {:halt, {:error, {:unreadable, package, {:names_no_item, id}}}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      refused -> refused
    end
  end

  # An href is relative to the package document and may carry a fragment, which names a
  # place inside a document rather than a document. Resolved against the archive's root so
  # that a `..` cannot reach outside it.
  defp beside(package, href) do
    path = href |> URI.parse() |> Map.get(:path) |> URI.decode()

    package
    |> Path.dirname()
    |> Path.join(path)
    |> Path.expand("/")
    |> String.trim_leading("/")
  end

  defp read_each(location, entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, so_far} ->
      case document(location, entry) do
        {:ok, text} -> {:cont, {:ok, [text | so_far]}}
        refused -> {:halt, refused}
      end
    end)
    |> case do
      {:ok, texts} -> {:ok, Enum.reverse(texts)}
      refused -> refused
    end
  end

  defp document(location, path) do
    state = %{text: [], skipping: 0, verbatim: 0}

    with {:ok, bytes} <- entry(location, path, @content),
         {:ok, %{text: text}} <- parse(bytes, path, &written/3, state) do
      {:ok, assembled(text)}
    end
  end

  # Prose and a listing are tidied differently and sit beside each other, so each run of
  # one kind is finished before the next begins: collapsing a listing's indentation would
  # change what the code means, and keeping prose's would print the document's own
  # indentation as though the author had meant it.
  defp assembled(chunks) do
    chunks
    |> Enum.reverse()
    |> Enum.chunk_by(fn {kind, _written} -> kind end)
    |> Enum.map_join("", fn [{kind, _first} | _rest] = run ->
      run |> Enum.map_join("", fn {_kind, written} -> written end) |> tidied(kind)
    end)
    |> String.trim()
  end

  defp entry(location, path, ceiling) do
    case Archive.read(location, path, ceiling) do
      {:ok, ""} -> {:error, {:no_entry, path}}
      {:ok, bytes} -> {:ok, bytes}
      {:error, refusal} -> {:error, {:unreadable, path, refusal}}
    end
  end

  defp parse(bytes, path, accumulate, state) do
    case Xml.read(bytes, accumulate, state) do
      {:ok, read} -> {:ok, read}
      {:error, refusal} -> {:error, {:unreadable, path, refusal}}
    end
  end

  defp rootfile({:startElement, _uri, name, _qname, attributes}, _location, named) do
    case {folded(name), attribute(attributes, "full-path")} do
      {"rootfile", path} when is_binary(path) -> [path | named]
      _another_element -> named
    end
  end

  defp rootfile(_event, _location, named), do: named

  defp package_of({:startElement, _uri, name, _qname, attributes}, _location, read) do
    case folded(name) do
      "item" ->
        with id when is_binary(id) <- attribute(attributes, "id"),
             href when is_binary(href) <- attribute(attributes, "href") do
          %{read | items: Map.put(read.items, id, href)}
        else
          _not_a_manifest_item -> read
        end

      "itemref" ->
        case attribute(attributes, "idref") do
          id when is_binary(id) -> %{read | spine: [id | read.spine]}
          nil -> read
        end

      _another_element ->
        read
    end
  end

  defp package_of(_event, _location, read), do: read

  # What is in `head` is about the document and what is in a script or a stylesheet is
  # not prose, so neither reaches the text. Counted rather than flagged, because one may
  # hold another and a flag cleared by the inner one would let the rest of the outer one
  # through.
  @hidden ~w(head script style)

  # Where a passage of prose ends. HTML has no character for it — the layout is the
  # renderer's — so what stands for one here is the flow content the publication is
  # written in, and an inline element inside it leaves the passage alone. A blank line
  # rather than a break, because the text is read as it is written: two paragraphs run
  # together by a single newline read as one.
  @ends_a_line ~w(p div li h1 h2 h3 h4 h5 h6 br tr blockquote pre figcaption
                  td th section article dd dt caption)

  # A listing is written the way it runs, so what is inside one is kept exactly: its line
  # breaks are the code's and its indentation is the code's meaning.
  @verbatim "pre"

  defp written({:startElement, _uri, name, _qname, _attributes}, _location, state) do
    case folded(name) do
      hidden when hidden in @hidden -> %{state | skipping: state.skipping + 1}
      @verbatim -> %{state | verbatim: state.verbatim + 1}
      "br" -> push(state, "\n")
      _shown -> state
    end
  end

  defp written({:endElement, _uri, name, _qname}, _location, state) do
    case folded(name) do
      hidden when hidden in @hidden ->
        %{state | skipping: state.skipping - 1}

      @verbatim ->
        state = %{state | verbatim: state.verbatim - 1}
        push(state, "\n\n")

      ends when ends in @ends_a_line ->
        push(state, "\n\n")

      _inline ->
        state
    end
  end

  defp written({:characters, written}, _location, %{skipping: 0} = state),
    do: push(state, to_string(written))

  # The whitespace between two elements is text the document wrote, and a parser that
  # offers it separately is still offering it: inside a listing it is the line breaks and
  # the indentation, and in prose it is the space between two words an element divided.
  defp written({:ignorableWhitespace, written}, _location, %{skipping: 0} = state),
    do: push(state, to_string(written))

  defp written(_event, _location, state), do: state

  defp push(%{verbatim: 0} = state, written),
    do: %{state | text: [{:flowed, written} | state.text]}

  defp push(state, written), do: %{state | text: [{:verbatim, written} | state.text]}

  # In prose a document's own line breaks are indentation rather than writing, so the
  # runs of space they leave are collapsed and a run of blank lines is one paragraph
  # break however many elements ended at once. In a listing nothing is collapsed, because
  # every space in it is the author's.
  defp tidied(text, :verbatim), do: String.normalize(text, :nfc)

  defp tidied(text, :flowed) do
    text
    |> String.replace(~r/[ \t\x{00A0}]*\n[ \t\x{00A0}]*/u, "\n")
    |> String.replace(~r/[ \t]+/, " ")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.normalize(:nfc)
  end

  defp folded(name), do: name |> to_string() |> String.downcase()

  # xmerl states an attribute as its namespace, its prefix, its name and its value, each
  # as a charlist.
  defp attribute(attributes, wanted) do
    Enum.find_value(attributes, fn {_uri, _prefix, name, value} ->
      folded(name) == wanted and to_string(value)
    end)
  end
end
