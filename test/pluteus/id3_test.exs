defmodule Pluteus.Id3Test do
  @moduledoc """
  An MP3's ID3v2 tag is read for the frames ffprobe leaves out: the recording identifier
  Picard keeps in `UFID`, and the ISRC in `TSRC` (spec-05 §9.1).

  Each tag is built here byte by byte as [ID3v2.3] and [ID3v2.4] lay it out, so what is
  under test is the format and not a tagger's habits.
  """

  use ExUnit.Case, async: true

  import Bitwise

  alias Pluteus.Id3

  @owner "http://musicbrainz.org"
  @recording "50193b06-d76a-466d-a5b0-304edf57befc"

  defp synchsafe(n),
    do: <<n >>> 21 &&& 0x7F, n >>> 14 &&& 0x7F, n >>> 7 &&& 0x7F, n &&& 0x7F>>

  defp tag(major, frames, opts \\ []) do
    flags = Keyword.get(opts, :flags, 0)
    body = IO.iodata_to_binary(frames) <> Keyword.get(opts, :padding, <<0, 0, 0, 0>>)
    "ID3" <> <<major, 0, flags>> <> synchsafe(byte_size(body)) <> body
  end

  defp frame(3, id, body, format), do: id <> <<byte_size(body)::32, 0, format>> <> body
  defp frame(4, id, body, format), do: id <> synchsafe(byte_size(body)) <> <<0, format>> <> body

  defp ufid(identifier), do: @owner <> <<0>> <> identifier
  defp tsrc(encoding, text), do: <<encoding>> <> text

  describe "the tag's length" do
    test "is read from its first ten bytes, header included" do
      bytes = tag(4, [frame(4, "UFID", ufid(@recording), 0)])
      assert Id3.tag_bytes(binary_part(bytes, 0, 10)) == {:ok, byte_size(bytes)}
    end

    test "a file with no tag at its head has none" do
      assert Id3.tag_bytes(<<0xFF, 0xFB, 0x90, 0x64, 0, 0, 0, 0, 0, 0>>) == :none
    end
  end

  describe "§9.1. The recording identifier Picard keeps in UFID" do
    for major <- [3, 4] do
      test "is read from a 2.#{major} tag, under its owner and no other" do
        bytes =
          tag(unquote(major), [
            frame(unquote(major), "TIT2", tsrc(0, "A title"), 0),
            frame(
              unquote(major),
              "UFID",
              "http://www.cddb.com/id3/taginfo1.html" <> <<0, 1, 2>>,
              0
            ),
            frame(unquote(major), "UFID", ufid(@recording), 0)
          ])

        assert {:ok, frames} = Id3.frames(bytes)
        assert Id3.unique_file_identifiers(frames, @owner) == {:ok, [@recording]}
      end
    end

    test "is read from a 2.2 tag's UFI frame, and its ISRC from TRC" do
      frames = [
        "TT2" <> <<8::24>> <> tsrc(0, "A title"),
        "UFI" <> <<byte_size(ufid(@recording))::24>> <> ufid(@recording),
        "TRC" <> <<13::24>> <> tsrc(0, "USRC17607839")
      ]

      {:ok, frames} = Id3.frames(tag(2, frames))
      assert Id3.unique_file_identifiers(frames, @owner) == {:ok, [@recording]}
      assert Id3.text(frames, "TSRC") == {:ok, ["USRC17607839"]}
    end

    test "past a frame whose identifier the format does not allow" do
      # A tagger wrote `Date`, in mixed case, with a size that reads correctly.
      bytes =
        tag(3, [
          frame(3, "Date", tsrc(0, "2010"), 0),
          frame(3, "UFID", ufid(@recording), 0)
        ])

      {:ok, frames} = Id3.frames(bytes)
      assert {"Date", _} = hd(frames)
      assert Id3.unique_file_identifiers(frames, @owner) == {:ok, [@recording]}
    end

    test "a tag carrying none answers none" do
      {:ok, frames} = Id3.frames(tag(4, [frame(4, "TIT2", tsrc(3, "A title"), 0)]))
      assert Id3.unique_file_identifiers(frames, @owner) == {:ok, []}
    end
  end

  describe "the ISRC in TSRC" do
    test "in each encoding a text frame may use" do
      utf16 = :unicode.characters_to_binary("USRC17607839", :utf8, {:utf16, :little})

      for {major, encoding, text} <- [
            {3, 0, "USRC17607839"},
            {3, 1, <<0xFF, 0xFE>> <> utf16},
            {4, 2, :unicode.characters_to_binary("USRC17607839", :utf8, {:utf16, :big})},
            {4, 3, "USRC17607839"}
          ] do
        {:ok, frames} = Id3.frames(tag(major, [frame(major, "TSRC", tsrc(encoding, text), 0)]))
        assert Id3.text(frames, "TSRC") == {:ok, ["USRC17607839"]}
      end
    end

    test "several values of a 2.4 frame, separated by a null" do
      {:ok, frames} =
        Id3.frames(tag(4, [frame(4, "TSRC", tsrc(3, "USRC17607839\0GBAYE0601498"), 0)]))

      assert Id3.text(frames, "TSRC") == {:ok, ["USRC17607839", "GBAYE0601498"]}
    end
  end

  describe "unsynchronisation is undone" do
    # An identifier holding $FF $E0, which unsynchronisation writes as $FF $00 $E0.
    @raw <<0x41, 0xFF, 0xE0, 0x42>>
    @written <<0x41, 0xFF, 0x00, 0xE0, 0x42>>

    test "over a whole 2.3 tag" do
      bytes = tag(3, [frame(3, "UFID", ufid(@raw), 0) |> unsynchronised()], flags: 0x80)

      {:ok, frames} = Id3.frames(bytes)
      assert Id3.unique_file_identifiers(frames, @owner) == {:ok, [@raw]}
    end

    test "in a 2.4 frame marked unsynchronised, with its data length indicator" do
      body = synchsafe(byte_size(ufid(@raw))) <> @owner <> <<0>> <> @written
      {:ok, frames} = Id3.frames(tag(4, [frame(4, "UFID", body, 0x03)]))

      assert Id3.unique_file_identifiers(frames, @owner) == {:ok, [@raw]}
    end
  end

  defp unsynchronised(frame), do: :binary.replace(frame, <<0xFF, 0xE0>>, <<0xFF, 0, 0xE0>>)

  describe "an extended header is stepped over" do
    test "in 2.3, whose size excludes itself" do
      extended = <<6::32, 0, 0, 0, 0, 0, 0>>
      bytes = tag(3, [extended, frame(3, "UFID", ufid(@recording), 0)], flags: 0x40)

      {:ok, frames} = Id3.frames(bytes)
      assert Id3.unique_file_identifiers(frames, @owner) == {:ok, [@recording]}
    end

    test "in 2.4, whose synchsafe size includes itself" do
      extended = synchsafe(6) <> <<1, 0>>
      bytes = tag(4, [extended, frame(4, "UFID", ufid(@recording), 0)], flags: 0x40)

      {:ok, frames} = Id3.frames(bytes)
      assert Id3.unique_file_identifiers(frames, @owner) == {:ok, [@recording]}
    end
  end

  describe "what is not read is said, and not taken for absence" do
    test "a compressed frame is an error naming it when it is asked for" do
      {:ok, frames} = Id3.frames(tag(4, [frame(4, "UFID", ufid(@recording), 0x09)]))
      assert Id3.unique_file_identifiers(frames, @owner) == {:error, {:unsupported, "UFID"}}
    end

    test "an encrypted 2.3 frame likewise" do
      {:ok, frames} = Id3.frames(tag(3, [frame(3, "TSRC", tsrc(0, "USRC17607839"), 0x40)]))
      assert Id3.text(frames, "TSRC") == {:error, {:unsupported, "TSRC"}}
    end

    test "a 2.2 tag marked compressed, which its document says to ignore" do
      assert Id3.frames("ID3" <> <<2, 0, 0x40, 0, 0, 0, 0>>) ==
               {:error, {:unsupported, "compressed tag"}}
    end

    test "a tag of a version the reader does not know" do
      assert Id3.frames("ID3" <> <<5, 0, 0, 0, 0, 0, 0>>) == {:error, {:unsupported_version, 5}}
    end

    test "a frame whose identifier is not text, where the frames are no longer aligned" do
      bytes = tag(3, [<<0xFF, 0xFB, 0x90, 0x64, 0::32, 0, 0>>])
      assert Id3.frames(bytes) == {:error, {:malformed, :frame_id}}
    end

    test "a tag shorter than its header says" do
      bytes = tag(4, [frame(4, "UFID", ufid(@recording), 0)])

      assert Id3.frames(binary_part(bytes, 0, byte_size(bytes) - 8)) ==
               {:error, {:truncated, :tag}}
    end

    test "a frame claiming more than the tag holds" do
      bytes = tag(3, ["UFID" <> <<500::32, 0, 0>> <> ufid(@recording)], padding: <<>>)
      assert Id3.frames(bytes) == {:error, {:truncated, :frame}}
    end

    test "no tag at all is none" do
      assert Id3.frames(<<0xFF, 0xFB, 0x90, 0x64>>) == :none
    end
  end
end
