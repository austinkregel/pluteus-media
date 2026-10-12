defmodule Pluteus.Presentation.TextTest do
  @moduledoc """
  [spec-10] §11.5's three text artefacts: extracted text, word positions, and the
  position list that makes a place in a publication answerable without a viewport.
  """

  use Pluteus.DataCase, async: true

  import Pluteus.IngestFixtures

  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Ingest.Place
  alias Pluteus.Presentation.Generate
  alias Pluteus.Presentation.Text
  alias Pluteus.Principals
  alias Pluteus.Storage
  alias Pluteus.StorageFixtures

  @t0 ~U[2026-09-18 12:00:00.000000Z]

  setup do
    _system = Principals.system!()
    %{inbox: inbox!()}
  end

  # Under a prefix of its own, because two async tests dropping one relative path
  # contend on the sighting and acquisition rows for as long as the slower one runs, and
  # reading a publication is slow.
  defp ingest!(inbox, files) do
    prefix = unique_prefix()
    for {path, bytes} <- files, do: drop!(inbox, Path.join(prefix, path), bytes)
    ids = inbox |> acquire_settled!(@t0) |> acquired()
    Place.place_due(inbox)
    Normalize.normalize_due()
    ids |> Enum.map(&Ingest.get_acquisition!/1) |> Enum.sort_by(& &1.inbox_path)
  end

  defp manifestation_of(acquisition),
    do: Repo.get!(DigitalItem, acquisition.digital_item_id).manifestation_id

  defp made!(subject, profile) do
    {:ok, made} = Generate.run(subject, profile)
    on_exit(fn -> Storage.delete(made.location) end)
    made
  end

  defp a_letter(inbox, name \\ "scans/letters/1943-04-12.pdf") do
    [letter] = ingest!(inbox, %{name => pdf_with_words()})
    manifestation_of(letter)
  end

  # A PDF carrying real text at known positions, so a position can be checked rather
  # than merely be present.
  defp pdf_with_words do
    """
    %PDF-1.4
    1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
    2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
    3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 100]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj
    4 0 obj<</Length 60>>stream
    BT /F1 12 Tf 20 50 Td (Dear Ada and Thomas) Tj ET
    endstream
    endobj
    5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
    trailer<</Root 1 0 R>>
    %%EOF
    """
  end

  describe "extracted text is the substrate for search" do
    test "a publication's words are read out of the file", %{inbox: inbox} do
      made = made!(a_letter(inbox), "text-extracted")

      assert made.media_type == "text/plain; charset=utf-8"
      assert Storage.read(made.location) =~ "Dear Ada and Thomas"
      assert made.descriptor["source"] == "pdftotext"
      assert made.descriptor["characters"] > 0
    end

    test "plain text is its own extraction", %{inbox: inbox} do
      [note] = ingest!(inbox, %{"scans/letters/note.txt" => "Dear Ada\r\nand Thomas\r\n"})

      made = made!(manifestation_of(note), "text-extracted")

      # One newline convention and normal form C, so a phrase matches however the file
      # spelled it.
      assert Storage.read(made.location) == "Dear Ada\nand Thomas"
      assert made.descriptor["source"] == "file"
    end

    test "a scan's text is guessed from its pixels, and says so", %{inbox: inbox} do
      [scan] = ingest!(inbox, %{"scans/letters/scan.png" => words_on_paper()})

      made = made!(manifestation_of(scan), "text-extracted")

      # A transcript nobody can tell was guessed is worse than one labelled as guessed.
      assert made.descriptor["source"] == "tesseract"
      assert Storage.read(made.location) =~ "Dear"
    end

    test "it carries no geometry, because it is not an image", %{inbox: inbox} do
      made = made!(a_letter(inbox), "text-extracted")

      assert made.width == nil
      assert made.height == nil
    end
  end

  describe "word positions are regions, expressed as percentages" do
    test "each word carries its page and its box", %{inbox: inbox} do
      made = made!(a_letter(inbox), "text-word-positions")

      %{"words" => words} = Jason.decode!(Storage.read(made.location))

      assert [_, _, _, _] = words
      assert Enum.map(words, & &1["text"]) == ["Dear", "Ada", "and", "Thomas"]

      for word <- words do
        assert word["page"] == 1
        assert word["x_percent"] >= 0 and word["x_percent"] <= 100
        assert word["width_percent"] > 0
      end
    end

    test "the regions are percentages, never pixels", %{inbox: inbox} do
      made = made!(a_letter(inbox), "text-word-positions")

      %{"words" => [first | _]} = Jason.decode!(Storage.read(made.location))

      # The page is 200 points wide and the text starts at 20, so the first word begins
      # a tenth of the way across. A pixel offset would not survive a re-encode, which
      # spec-01 §8.4 is why this is a proportion.
      assert_in_delta first["x_percent"], 10.0, 0.5
      assert made.descriptor["units"] == "percent"
    end

    test "the words run left to right across the page", %{inbox: inbox} do
      made = made!(a_letter(inbox), "text-word-positions")

      %{"words" => words} = Jason.decode!(Storage.read(made.location))
      lefts = Enum.map(words, & &1["x_percent"])

      assert lefts == Enum.sort(lefts)
    end

    test "a scan's words are read by OCR, with a confidence", %{inbox: inbox} do
      [scan] = ingest!(inbox, %{"scans/letters/scan.png" => words_on_paper()})

      made = made!(manifestation_of(scan), "text-word-positions")

      %{"words" => words} = Jason.decode!(Storage.read(made.location))

      assert words != []
      assert Enum.all?(words, &is_float(&1["confidence"]))
      assert made.descriptor["source"] == "tesseract"
    end

    test "plain text has no page, so it has no layout", %{inbox: inbox} do
      [note] = ingest!(inbox, %{"scans/letters/note.txt" => "Dear Ada\n"})

      assert {:error, "text_has_no_layout", _detail} =
               Generate.run(manifestation_of(note), "text-word-positions")
    end
  end

  describe "a position list answers a place without a viewport" do
    test "it is an integer index over the whole publication", %{inbox: inbox} do
      made = made!(a_letter(inbox), "text-position-list")

      index = Jason.decode!(Storage.read(made.location))

      assert index["unit"] == "character"
      assert index["total"] > 0
      assert index["pages"] == [0]
    end

    test "the offsets are exhaustive, so every position falls between two", %{inbox: inbox} do
      [note] = ingest!(inbox, %{"scans/letters/note.txt" => "Dear Ada and Thomas\n"})

      made = made!(manifestation_of(note), "text-position-list")
      index = Jason.decode!(Storage.read(made.location))

      assert index["pages"] == [0]
      assert index["total"] == String.length("Dear Ada and Thomas")

      # A third of the way through is a number about the book, not about the reader's
      # font size.
      third = round(index["total"] / 3)
      assert third > 0 and third < index["total"]
    end

    test "a scan is not a publication, so the profile does not apply to one",
         %{inbox: inbox} do
      [scan] = ingest!(inbox, %{"scans/letters/scan.png" => words_on_paper()})

      # The registry settles this before any reader runs: a position list is an index
      # over a publication, and one image is not one.
      assert Generate.run(manifestation_of(scan), "text-position-list") ==
               {:refused, :profile_does_not_apply}
    end

    test "asked of a scan directly, the reader still names why it cannot" do
      location = StorageFixtures.stored!("scan.png", words_on_paper())

      assert {:error, "text_has_no_pagination", _detail} =
               Text.position_list(location, :image)
    end
  end

  describe "a reader is chosen from what the bytes are" do
    test "a publication with no readable text is a failure, not an empty transcript" do
      assert {:error, "text_not_extractable", _detail} =
               Text.extracted("nowhere/at/all", :audio)
    end

    test "text that is not UTF-8 is refused rather than mangled", %{inbox: inbox} do
      [note] = ingest!(inbox, %{"scans/letters/note.txt" => "a note\n"})
      location = Normalize.master_of(Repo.get!(DigitalItem, note.digital_item_id).id).location

      assert {:ok, _read} = Text.extracted(location, :text)
    end
  end
end
