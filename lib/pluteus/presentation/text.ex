defmodule Pluteus.Presentation.Text do
  @moduledoc """
  A publication's words, and where they sit ([spec-10] §11.5).

  Three artefacts from one reading. **Extracted text** is the substrate for search and
  for anchoring an annotation to a phrase. **Word positions** are the per-word regions
  that let a scan be overlaid with its own transcript, so a person can point at a word
  in the image. A **position list** is an exhaustive integer index over the publication.

  The position list exists because reflowable text has no stable coordinate until a
  viewport exists. Without it, "a third of the way through" is a question about the
  reader's font size rather than about the book, and the answer changes when the reader
  changes the size. With it, the question is about an index the publication carries.

  Where the text is in the file it is read from the file, and where it is in the pixels
  it is read by OCR. Those are different operations with different reliability, and the
  artefact records which was used: a transcript nobody can tell was guessed is worse
  than one labelled as guessed.

  **Regions are percentages, never pixels.** spec-01 §8.4 forbids pixel offsets as an
  addressing basis because they do not survive a re-encode, and a word's box is a region
  in exactly that sense.
  """

  alias Pluteus.Storage

  @doc """
  The text of a publication, and how it was read.
  """
  @spec extracted(String.t(), atom()) ::
          {:ok, %{text: String.t(), source: String.t()}} | {:error, String.t(), map()}
  def extracted(location, class) do
    case reader(location, class) do
      {:pdf, path} -> some_text(from_pdf(path))
      {:ocr, path} -> some_text(from_ocr(path))
      {:plain, path} -> some_text(from_plain(path))
      :none -> {:error, "text_not_extractable", %{class: class}}
    end
  end

  # A publication with no readable text has no extracted text, and an empty artefact
  # standing for one is the mistake criterion 9 names in the other direction: nothing
  # is written to stand for what is not there. A photograph OCRs to nothing, which is
  # the true answer about a photograph.
  defp some_text({:ok, %{text: ""}}), do: {:error, "text_not_found", %{characters: 0}}
  defp some_text(read), do: read

  @doc """
  Every word and the region it occupies, as percentages of its page.
  """
  @spec word_positions(String.t(), atom()) ::
          {:ok, %{words: [map()], source: String.t()}} | {:error, String.t(), map()}
  def word_positions(location, class) do
    case reader(location, class) do
      {:pdf, path} -> pdf_words(path)
      {:ocr, path} -> ocr_words(path)
      {:plain, _path} -> {:error, "text_has_no_layout", %{reason: "plain text has no page"}}
      :none -> {:error, "text_not_extractable", %{class: class}}
    end
  end

  @doc """
  The index that makes a position in a publication answerable without a viewport.

  The offsets each page begins at, in characters, and the total. A surface wanting a
  third of the way through multiplies the total and finds the page whose offset it falls
  in; neither number moves when a reader changes the font size.
  """
  @spec position_list(String.t(), atom()) ::
          {:ok, map()} | {:error, String.t(), map()}
  def position_list(location, class) do
    case reader(location, class) do
      {:pdf, path} -> pdf_positions(path)
      {:plain, path} -> plain_positions(path)
      {:ocr, _path} -> {:error, "text_has_no_pagination", %{reason: "a scan is one page"}}
      :none -> {:error, "text_not_extractable", %{class: class}}
    end
  end

  # PRONOM's PDF identifiers are what placement recorded, but the reader is chosen from
  # the broad class and the format together: a document may be a PDF or plain text, and
  # an image's text is in its pixels whatever encoded them.
  defp reader(location, class) do
    path = Storage.path(location)

    cond do
      not File.exists?(path) -> :none
      pdf?(path) -> {:pdf, path}
      class == :image -> {:ocr, path}
      class in [:text, :companion] -> {:plain, path}
      true -> :none
    end
  end

  defp pdf?(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 5)) do
      {:ok, "%PDF-"} -> true
      _not_a_pdf -> false
    end
  end

  defp from_pdf(path) do
    case run("pdftotext", ["-layout", "-enc", "UTF-8", path, "-"]) do
      {:ok, text} -> {:ok, %{text: normalise(text), source: "pdftotext"}}
      error -> error
    end
  end

  defp from_ocr(path) do
    case run("tesseract", [path, "-", "--psm", "3"]) do
      {:ok, text} -> {:ok, %{text: normalise(text), source: "tesseract"}}
      error -> error
    end
  end

  defp from_plain(path) do
    bytes = File.read!(path)

    if String.valid?(bytes) do
      {:ok, %{text: normalise(bytes), source: "file"}}
    else
      {:error, "text_is_not_utf8", %{bytes: byte_size(bytes)}}
    end
  end

  # §11.5's normalised text: one newline convention and normal form C, so that a phrase
  # a person searched for matches a phrase the file spells the other way.
  defp normalise(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.normalize(:nfc)
    |> String.trim()
  end

  defp pdf_words(path) do
    with {:ok, xml} <- run("pdftotext", ["-bbox", "-enc", "UTF-8", path, "-"]) do
      {:ok, %{words: parse_bbox(xml), source: "pdftotext"}}
    end
  end

  # poppler writes one `page` element per page and one `word` per word, each with its
  # box in points. The page's own size is what turns those into percentages.
  defp parse_bbox(xml) do
    pages = Regex.scan(~r/<page width="([\d.]+)" height="([\d.]+)">(.*?)<\/page>/s, xml)

    pages
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {[_all, width, height, body], page} ->
      {page_width, _} = Float.parse(width)
      {page_height, _} = Float.parse(height)

      ~r/<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)<\/word>/s
      |> Regex.scan(body)
      |> Enum.map(fn [_all, x_min, y_min, x_max, y_max, word] ->
        region(page, word, {x_min, y_min, x_max, y_max}, page_width, page_height)
      end)
    end)
  end

  defp region(page, word, {x_min, y_min, x_max, y_max}, page_width, page_height) do
    {left, _} = Float.parse(x_min)
    {top, _} = Float.parse(y_min)
    {right, _} = Float.parse(x_max)
    {bottom, _} = Float.parse(y_max)

    %{
      "page" => page,
      "text" => word |> unescape() |> String.normalize(:nfc),
      "x_percent" => percent(left, page_width),
      "y_percent" => percent(top, page_height),
      "width_percent" => percent(right - left, page_width),
      "height_percent" => percent(bottom - top, page_height)
    }
  end

  defp ocr_words(path) do
    with {:ok, tsv} <- run("tesseract", [path, "-", "tsv"]),
         {:ok, {width, height}} <- ocr_page_size(path) do
      {:ok, %{words: parse_tsv(tsv, width, height), source: "tesseract"}}
    end
  end

  # Level 5 is a word; the coarser levels are the page, its blocks, paragraphs and
  # lines, which are the same regions aggregated and would be counted twice.
  defp parse_tsv(tsv, page_width, page_height) do
    tsv
    |> String.split("\n", trim: true)
    |> Enum.drop(1)
    |> Enum.map(&String.split(&1, "\t"))
    |> Enum.filter(&match?(["5" | _], &1))
    |> Enum.flat_map(fn row -> tsv_word(row, page_width, page_height) end)
  end

  defp tsv_word(
         [_level, page, _block, _par, _line, _word, left, top, width, height, confidence | rest],
         page_width,
         page_height
       ) do
    text = rest |> Enum.join("\t") |> String.trim()

    if text == "" do
      []
    else
      [
        %{
          "page" => String.to_integer(page),
          "text" => String.normalize(text, :nfc),
          "x_percent" => percent(String.to_integer(left), page_width),
          "y_percent" => percent(String.to_integer(top), page_height),
          "width_percent" => percent(String.to_integer(width), page_width),
          "height_percent" => percent(String.to_integer(height), page_height),
          "confidence" => confidence |> Float.parse() |> then(fn {value, _} -> value end)
        }
      ]
    end
  end

  defp tsv_word(_short_row, _page_width, _page_height), do: []

  defp ocr_page_size(path) do
    case run("vipsheader", ["-f", "width", path]) do
      {:ok, width} ->
        case run("vipsheader", ["-f", "height", path]) do
          {:ok, height} -> {:ok, {to_number(width), to_number(height)}}
          error -> error
        end

      error ->
        error
    end
  end

  defp pdf_positions(path) do
    with {:ok, xml} <- run("pdftotext", ["-bbox", "-enc", "UTF-8", path, "-"]) do
      {:ok, index(page_texts(xml), "pdftotext")}
    end
  end

  defp plain_positions(path) do
    with {:ok, %{text: text}} <- from_plain(path) do
      {:ok, index([text], "file")}
    end
  end

  # The offsets are cumulative character counts, so the list is exhaustive over the
  # publication: every position in the text falls between two of them.
  defp index(pages, source) do
    {offsets, total} =
      Enum.map_reduce(pages, 0, fn page, offset ->
        {offset, offset + String.length(page)}
      end)

    %{
      "unit" => "character",
      "total" => total,
      "pages" => offsets,
      "source" => source
    }
  end

  defp page_texts(xml) do
    ~r/<page width="[\d.]+" height="[\d.]+">(.*?)<\/page>/s
    |> Regex.scan(xml)
    |> Enum.map(fn [_all, body] ->
      ~r/<word[^>]*>(.*?)<\/word>/s
      |> Regex.scan(body)
      |> Enum.map_join(" ", fn [_all, word] -> unescape(word) end)
    end)
  end

  defp unescape(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
  end

  defp percent(_part, whole) when whole <= 0, do: 0.0
  defp percent(part, whole), do: Float.round(part / whole * 100, 4)

  defp to_number(text) do
    {value, _rest} = text |> String.trim() |> Integer.parse()
    value
  end

  # poppler and tesseract both write their complaints to standard error and their answer
  # to standard output, so the two are kept apart: a syntax warning about a trailer is
  # not part of a publication's text.
  defp run(command, args) do
    case System.cmd(command, args, stderr_to_stdout: false) do
      {output, 0} ->
        {:ok, output}

      {output, status} ->
        {:error, "text_reader_failed", %{command: command, status: status, output: output}}
    end
  end
end
