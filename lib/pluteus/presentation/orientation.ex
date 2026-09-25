defmodule Pluteus.Presentation.Orientation do
  @moduledoc """
  The orientation a still image states about itself, and the filter that applies it
  ([spec-10] §11.2, criterion 29).

  **Every derivative has its orientation applied and its metadata removed.** A
  derivative that asks its consumer to rotate it will be displayed rotated: a web
  page honours EXIF on an `<img>` and a canvas does not, a thumbnail in a grid is
  drawn by whichever of those the surface reached for, and the same bytes then appear
  the right way up in one place and on their side in another.

  **ffmpeg applies a JPEG's EXIF orientation itself**, on input: a 64 by 48 image
  stating `Orientation = 6` decodes as 48 by 64, and `-noautorotate` is what turns
  that off. So no filter is added for it, and adding one turns the image twice.

  What this is for is the other half of the criterion and the check on the first. The
  derivative must carry no orientation of its own, or a consumer that honours EXIF
  turns it again — `-map_metadata -1` discharges that, and `of/1` is how a test reads
  the result back. And `turns?/1` says whether a stated orientation should have
  exchanged the dimensions, so that the turn is verified rather than trusted: a
  future encoder that stopped autorotating would otherwise produce sideways thumbnails
  silently, which is exactly what this criterion exists to prevent.

  An image stating no orientation, or stating one this cannot parse, is treated as
  upright. That is the ordinary case rather than a failure: most images carry no EXIF
  at all, and a truncated APP1 segment in a file that otherwise decodes is not a
  reason to refuse to make a thumbnail of it.
  """

  @values 1..8

  # A JPEG's EXIF sits in an APP1 segment near the front of the file. Reading more
  # than this to find it would be reading the image.
  @head_bytes 65_536

  @doc """
  How much of a file's head carries the orientation, where one is stated.
  """
  @spec head_bytes() :: pos_integer()
  def head_bytes, do: @head_bytes

  @doc """
  The orientation these bytes state, from 1 to 8, or nil where they state none.
  """
  @spec of(binary()) :: 1..8 | nil
  def of(bytes) when is_binary(bytes) do
    case tiff_block(bytes) do
      nil -> nil
      tiff -> orientation_in(tiff)
    end
  end

  @doc """
  Whether applying an orientation exchanges an image's width and height.

  Five through eight are the quarter turns and their mirrors; one through four leave
  the axes where they are.
  """
  @spec turns?(1..8 | nil) :: boolean()
  def turns?(orientation), do: orientation in 5..8

  # A JPEG announces itself, and a TIFF is its own EXIF container.
  defp tiff_block(<<0xFF, 0xD8, rest::binary>>), do: app1(rest)
  defp tiff_block(<<"II", 0x2A, 0x00, _::binary>> = tiff), do: tiff
  defp tiff_block(<<"MM", 0x00, 0x2A, _::binary>> = tiff), do: tiff
  defp tiff_block(_not_an_image_with_exif), do: nil

  # Walking the marker segments to APP1. Image data begins at SOS, so anything not
  # found by then is not there.
  defp app1(<<0xFF, 0xDA, _::binary>>), do: nil
  defp app1(<<0xFF, 0xD9, _::binary>>), do: nil

  defp app1(<<0xFF, 0xFF, rest::binary>>), do: app1(<<0xFF, rest::binary>>)

  defp app1(<<0xFF, marker, rest::binary>>) when marker in 0xD0..0xD8, do: app1(rest)

  defp app1(<<0xFF, 0xE1, length::16, rest::binary>>) do
    case payload(rest, length) do
      {<<"Exif", 0, 0, tiff::binary>>, _after} -> tiff
      {_other_app1, after_it} -> app1(after_it)
      nil -> nil
    end
  end

  defp app1(<<0xFF, _marker, length::16, rest::binary>>) do
    case payload(rest, length) do
      {_skipped, after_it} -> app1(after_it)
      nil -> nil
    end
  end

  defp app1(_truncated), do: nil

  defp payload(rest, length) do
    size = max(length - 2, 0)

    if byte_size(rest) < size do
      nil
    else
      <<segment::binary-size(size), after_it::binary>> = rest
      {segment, after_it}
    end
  end

  defp orientation_in(<<"II", 0x2A, 0x00, offset::little-32, _::binary>> = tiff),
    do: entry(tiff, offset, :little)

  defp orientation_in(<<"MM", 0x00, 0x2A, offset::big-32, _::binary>> = tiff),
    do: entry(tiff, offset, :big)

  defp orientation_in(_no_tiff_header), do: nil

  # IFD0 is a count and then fixed-width entries: tag, type, count, value. Tag
  # 0x0112 is the orientation, and a SHORT's value sits in the first two bytes of
  # the entry's value field.
  defp entry(tiff, offset, endian) do
    with true <- offset >= 8 and offset + 2 <= byte_size(tiff),
         count = read16(tiff, offset, endian),
         true <- count > 0 and offset + 2 + count * 12 <= byte_size(tiff),
         stated when stated in @values <- orientation_tag(tiff, offset, count, endian) do
      stated
    else
      _stating_none -> nil
    end
  end

  defp orientation_tag(tiff, offset, count, endian) do
    Enum.find_value(0..(count - 1)//1, fn index ->
      at = offset + 2 + index * 12

      if read16(tiff, at, endian) == 0x0112, do: read16(tiff, at + 8, endian)
    end)
  end

  defp read16(binary, at, :big) do
    <<value::big-16>> = binary_part(binary, at, 2)
    value
  end

  defp read16(binary, at, :little) do
    <<value::little-16>> = binary_part(binary, at, 2)
    value
  end
end
