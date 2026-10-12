defmodule Pluteus.PublicationTest do
  @moduledoc """
  Reading a publication of several documents ([spec-10] §11.5, §12.1).

  What is asserted is the reading order and the refusals, because both are properties of
  somebody else's file: the order is the publication's own and not the archive's, and a
  publication that contradicts itself or reaches outside itself is refused naming what it
  did rather than read for whatever parsed first.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Publication
  alias Pluteus.Storage

  setup do
    location = "publications/#{System.unique_integer([:positive])}.epub"

    on_exit(fn -> Storage.delete(location) end)

    %{at: location}
  end

  describe "§11.5. A publication reads in the order its package states" do
    test "the documents are its spine's, in the spine's order", %{at: at} do
      held(at, [
        {"OEBPS/cover.html", page("A cover")},
        {"OEBPS/ch01.html", page("The first chapter")},
        {"OEBPS/ch02.html", page("The second chapter")}
      ])

      assert {:ok, [cover, first, second]} = Publication.divisions(at)
      assert cover == "A cover"
      assert first == "The first chapter"
      assert second == "The second chapter"
    end

    test "a document's markup is not its text", %{at: at} do
      held(at, [
        {"OEBPS/cover.html",
         """
         <?xml version="1.0" encoding="UTF-8"?>
         <html xmlns="http://www.w3.org/1999/xhtml">
           <head>
             <title>Not the text</title>
             <style>p { color: red }</style>
             <script>var hidden = "not the text"</script>
           </head>
           <body>
             <h1>A title</h1>
             <p>A paragraph with <em>emphasis</em> inside it.</p>
             <p>A second paragraph.</p>
           </body>
         </html>
         """}
      ])

      assert {:ok, [text]} = Publication.divisions(at)

      assert text == "A title\n\nA paragraph with emphasis inside it.\n\nA second paragraph."
      refute text =~ "Not the text"
      refute text =~ "color"
      refute text =~ "var hidden"
    end

    # A listing's whitespace is what it means: a language that indents its blocks says
    # what belongs to what with the spaces a reader would otherwise collapse.
    test "a listing keeps the spacing it was written with", %{at: at} do
      held(at, [
        {"OEBPS/ch01.html",
         """
         <?xml version="1.0" encoding="UTF-8"?>
         <html xmlns="http://www.w3.org/1999/xhtml"><body>
           <p>Then     the   allocation:</p>
           <pre data-type="programlisting"><code class="k">def</code> allocate(line, batches):
             batch = next(b for b in batches)
             batch.allocate(line)
         </pre>
         </body></html>
         """}
      ])

      assert {:ok, [text]} = Publication.divisions(at)

      assert text =~
               "def allocate(line, batches):\n" <>
                 "    batch = next(b for b in batches)\n    batch.allocate(line)"

      assert text =~ "Then the allocation:"
    end

    # The publication says which documents are the publication, so an image or a
    # stylesheet in the same archive is not one of them.
    test "what the spine does not name is not read", %{at: at} do
      held(at, [{"OEBPS/cover.html", page("A cover")}], %{
        "OEBPS/notes.html" => page("Nobody reads this")
      })

      assert {:ok, [text]} = Publication.divisions(at)
      refute text =~ "Nobody reads this"
    end
  end

  describe "§11.5. A publication that cannot be read says what it was reading" do
    test "a spine naming nothing the manifest carries is refused", %{at: at} do
      bytes =
        archive([
          {"META-INF/container.xml", container("OEBPS/content.opf")},
          {"OEBPS/content.opf",
           """
           <?xml version="1.0" encoding="UTF-8"?>
           <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
             <manifest><item id="cover" href="cover.html" media-type="application/xhtml+xml"/></manifest>
             <spine><itemref idref="chapter-nobody-declared"/></spine>
           </package>
           """},
          {"OEBPS/cover.html", page("A cover")}
        ])

      Storage.put(at, bytes)

      assert {:error, {:unreadable, "OEBPS/content.opf", {:names_no_item, named}}} =
               Publication.divisions(at)

      assert named == "chapter-nobody-declared"
    end

    test "a document that names something outside itself is refused naming it", %{at: at} do
      held(at, [
        {"OEBPS/cover.html",
         """
         <?xml version="1.0" encoding="UTF-8"?>
         <!DOCTYPE html [<!ENTITY theirs SYSTEM "file:///etc/passwd">]>
         <html xmlns="http://www.w3.org/1999/xhtml"><body><p>&theirs;</p></body></html>
         """}
      ])

      assert {:error, {:unreadable, "OEBPS/cover.html", {:names_outside_itself, named}}} =
               Publication.divisions(at)

      assert named == ["file:///etc/passwd"]
    end

    test "a spine naming a document the archive does not hold is refused", %{at: at} do
      bytes =
        archive([
          {"META-INF/container.xml", container("OEBPS/content.opf")},
          {"OEBPS/content.opf",
           """
           <?xml version="1.0" encoding="UTF-8"?>
           <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
             <manifest><item id="gone" href="gone.html" media-type="application/xhtml+xml"/></manifest>
             <spine><itemref idref="gone"/></spine>
           </package>
           """}
        ])

      Storage.put(at, bytes)

      assert {:error, {:unreadable, "OEBPS/gone.html", _refusal}} = Publication.divisions(at)
    end
  end

  describe "§5. What a publication is comes from its own bytes" do
    test "a publication says so in the place its own format fixes", %{at: at} do
      held(at, [{"OEBPS/cover.html", page("A cover")}])

      assert Publication.publication?(at)
    end

    test "an archive that is not one does not", %{at: at} do
      Storage.put(at, zipped([{"images/001.txt", "a page of a comic, not a book"}]))

      refute Publication.publication?(at)
    end
  end

  # A publication whose spine is every document given, in the order given, which is what
  # makes the order assertable: the archive holds them in whichever order it likes.
  defp held(location, spine, beside \\ %{}) do
    ordered = Enum.map(spine, fn {path, _bytes} -> path end)

    manifest =
      Enum.map_join(ordered, "\n", fn path ->
        ~s|<item id="#{id(path)}" href="#{Path.basename(path)}" | <>
          ~s|media-type="application/xhtml+xml"/>|
      end)

    itemrefs = Enum.map_join(ordered, "\n", &~s|<itemref idref="#{id(&1)}"/>|)

    package = """
    <?xml version="1.0" encoding="UTF-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
      <manifest>#{manifest}</manifest>
      <spine>#{itemrefs}</spine>
    </package>
    """

    entries =
      [{"META-INF/container.xml", container("OEBPS/content.opf")}, {"OEBPS/content.opf", package}] ++
        Enum.reverse(spine) ++ Enum.to_list(beside)

    Storage.put(location, archive(entries))
  end

  defp id(path), do: path |> Path.basename() |> Path.rootname()

  defp container(package) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
      <rootfiles><rootfile full-path="#{package}" media-type="application/oebps-package+xml"/></rootfiles>
    </container>
    """
  end

  defp page(text) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml"><body><p>#{text}</p></body></html>
    """
  end

  # The format fixes the first entry and what is in it, so the fixture writes that entry
  # first. Everything is stored rather than deflated, which is what the format requires of
  # that one and is no worse for the rest.
  defp archive(entries), do: zipped([{"mimetype", "application/epub+zip"} | entries])

  defp zipped(entries) do
    files = for {path, bytes} <- entries, do: {String.to_charlist(path), bytes}

    {:ok, {_name, bytes}} =
      :zip.create(~c"publication.epub", files, [:memory, {:uncompress, :all}])

    bytes
  end
end
