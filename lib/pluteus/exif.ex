defmodule Pluteus.Exif do
  @moduledoc """
  Reads what a still image's EXIF states about it: the TIFF structure inside a JPEG's APP1
  segment, or a TIFF file's own.

  **Absent and malformed are different answers.** An image carrying no EXIF, or EXIF with
  no block for what was asked, states nothing, and that is the ordinary case: `:none`. One
  whose block is there but cannot be read is `{:error, why}`, because a coordinate that
  was written and then lost is not the same as one that was never written, and a caller
  deciding where a photograph was taken must be able to tell them apart. A caller for whom
  the difference does not matter discards it itself.

  Only the head of a file is read. A JPEG's APP1 segment is at most 64 KiB and sits before
  the image data, so anything EXIF states is within it; an offset reaching past what was
  read is an error saying so rather than a silence.
  """

  @head_bytes 65_536

  # TIFF field types: their numbers and the size of one value of each.
  @sizes %{1 => 1, 2 => 1, 3 => 2, 4 => 4, 5 => 8, 7 => 1, 9 => 4, 10 => 8}

  @orientation 0x0112
  @gps_ifd 0x8825

  # The GPS block's tags (EXIF 2.32 §4.6.6).
  @latitude_ref 0x0001
  @latitude 0x0002
  @longitude_ref 0x0003
  @longitude 0x0004
  @status 0x0009
  @positioning_error 0x001F

  @typedoc "A TIFF structure, its byte order, and where its first IFD is."
  @type tiff :: %{bytes: binary(), endian: :big | :little, ifd0: non_neg_integer()}

  @typedoc "Why a block that is present could not be read."
  @type unreadable :: {:truncated, atom()} | {:malformed, atom()}

  @typedoc """
  A position as the image states it: degrees north and east, and the horizontal error the
  device stated in metres, or nil where it stated none.
  """
  @type position :: %{latitude: float(), longitude: float(), accuracy: float() | nil}

  @doc """
  How much of a file's head carries its EXIF.
  """
  @spec head_bytes() :: pos_integer()
  def head_bytes, do: @head_bytes

  @doc """
  The orientation these bytes state, from 1 to 8.
  """
  @spec orientation(binary()) :: {:ok, 1..8} | :none | {:error, unreadable()}
  def orientation(bytes) do
    with {:ok, tiff} <- tiff(bytes),
         {:ok, ifd0} <- ifd(tiff, tiff.ifd0, :ifd0) do
      case Map.fetch(ifd0, @orientation) do
        :error -> :none
        {:ok, entry} -> orientation_value(value(tiff, entry, :orientation))
      end
    end
  end

  defp orientation_value({:ok, stated}) when stated in 1..8, do: {:ok, stated}
  defp orientation_value({:ok, _outside}), do: {:error, {:malformed, :orientation}}
  defp orientation_value({:error, _} = unreadable), do: unreadable

  @doc """
  The position these bytes state.

  `:none` where the image carries no GPS block, where the block states no coordinate, or
  where the device marked its measurement void (`GPSStatus` of `V`).
  """
  @spec position(binary()) :: {:ok, position()} | :none | {:error, unreadable()}
  def position(bytes) do
    with {:ok, tiff} <- tiff(bytes),
         {:ok, ifd0} <- ifd(tiff, tiff.ifd0, :ifd0),
         {:ok, gps_entry} <- present(ifd0, @gps_ifd),
         {:ok, gps_offset} <- value(tiff, gps_entry, :gps_ifd),
         {:ok, gps} <- ifd(tiff, gps_offset, :gps_ifd),
         :measured <- status(tiff, gps),
         {:ok, _} <- present(gps, @latitude) do
      read_position(tiff, gps)
    end
  end

  defp present(ifd, tag) do
    case Map.fetch(ifd, tag) do
      {:ok, entry} -> {:ok, entry}
      :error -> :none
    end
  end

  defp status(tiff, gps) do
    case Map.fetch(gps, @status) do
      :error -> :measured
      {:ok, entry} -> status_value(value(tiff, entry, :gps_status))
    end
  end

  defp status_value({:ok, "A"}), do: :measured
  defp status_value({:ok, "V"}), do: :none
  defp status_value({:ok, _other}), do: {:error, {:malformed, :gps_status}}
  defp status_value({:error, _} = unreadable), do: unreadable

  defp read_position(tiff, gps) do
    with {:ok, latitude} <-
           coordinate(tiff, gps, @latitude, @latitude_ref, %{"N" => 1, "S" => -1}, 90, :latitude),
         {:ok, longitude} <-
           coordinate(
             tiff,
             gps,
             @longitude,
             @longitude_ref,
             %{"E" => 1, "W" => -1},
             180,
             :longitude
           ),
         {:ok, accuracy} <- accuracy(tiff, gps) do
      {:ok, %{latitude: latitude, longitude: longitude, accuracy: accuracy}}
    end
  end

  # Degrees, minutes and seconds as three rationals, and a reference saying which
  # hemisphere. A coordinate with no reference does not say which side of the equator or
  # the meridian it is on, so it is not a coordinate.
  defp coordinate(tiff, gps, tag, ref_tag, signs, bound, name) do
    with {:ok, entry} <- required(gps, tag, name),
         {:ok, ref_entry} <- required(gps, ref_tag, name),
         {:ok, [_, _, _] = dms} <- value(tiff, entry, name),
         {:ok, ref} <- value(tiff, ref_entry, name),
         {:ok, sign} <- sign(signs, ref, name),
         {:ok, [degrees, minutes, seconds]} <- quotients(dms, name) do
      within(sign * (degrees + minutes / 60 + seconds / 3600), bound, name)
    else
      {:ok, _not_three} -> {:error, {:malformed, name}}
      other -> other
    end
  end

  defp required(ifd, tag, name) do
    case Map.fetch(ifd, tag) do
      {:ok, entry} -> {:ok, entry}
      :error -> {:error, {:malformed, name}}
    end
  end

  defp sign(signs, ref, name) do
    case Map.fetch(signs, ref) do
      {:ok, sign} -> {:ok, sign}
      :error -> {:error, {:malformed, name}}
    end
  end

  defp within(degrees, bound, _name) when degrees >= -bound and degrees <= bound,
    do: {:ok, degrees}

  defp within(_degrees, _bound, name), do: {:error, {:malformed, name}}

  defp accuracy(tiff, gps) do
    case Map.fetch(gps, @positioning_error) do
      :error ->
        {:ok, nil}

      {:ok, entry} ->
        with {:ok, [rational]} <- value(tiff, entry, :positioning_error),
             {:ok, [metres]} <- quotients([rational], :positioning_error) do
          {:ok, metres}
        else
          {:ok, _not_one} -> {:error, {:malformed, :positioning_error}}
          unreadable -> unreadable
        end
    end
  end

  defp quotients(rationals, name) do
    if Enum.any?(rationals, fn {_numerator, denominator} -> denominator == 0 end) do
      {:error, {:malformed, name}}
    else
      {:ok, Enum.map(rationals, fn {numerator, denominator} -> numerator / denominator end)}
    end
  end

  # --- The TIFF structure ------------------------------------------------------------

  @doc """
  The TIFF structure these bytes carry: a JPEG's EXIF, or a TIFF file itself.
  """
  @spec tiff(binary()) :: {:ok, tiff()} | :none | {:error, unreadable()}
  def tiff(<<0xFF, 0xD8, rest::binary>>), do: rest |> app1() |> header()
  def tiff(<<"II", 0x2A, 0x00, _::binary>> = tiff), do: header({:ok, tiff})
  def tiff(<<"MM", 0x00, 0x2A, _::binary>> = tiff), do: header({:ok, tiff})
  def tiff(_not_an_image_with_exif), do: :none

  defp header({:ok, <<"II", 0x2A, 0x00, ifd0::little-32, _::binary>> = bytes}),
    do: {:ok, %{bytes: bytes, endian: :little, ifd0: ifd0}}

  defp header({:ok, <<"MM", 0x00, 0x2A, ifd0::big-32, _::binary>> = bytes}),
    do: {:ok, %{bytes: bytes, endian: :big, ifd0: ifd0}}

  defp header({:ok, _no_tiff_header}), do: {:error, {:malformed, :tiff_header}}
  defp header(other), do: other

  # Walking the marker segments to APP1. Image data begins at SOS, so anything not found
  # by then is not there.
  defp app1(<<0xFF, 0xDA, _::binary>>), do: :none
  defp app1(<<0xFF, 0xD9, _::binary>>), do: :none
  defp app1(<<0xFF, 0xFF, rest::binary>>), do: app1(<<0xFF, rest::binary>>)
  defp app1(<<0xFF, marker, rest::binary>>) when marker in 0xD0..0xD8, do: app1(rest)

  defp app1(<<0xFF, 0xE1, length::16, rest::binary>>) do
    case segment(rest, length) do
      {:ok, <<"Exif", 0, 0, tiff::binary>>, _after} -> {:ok, tiff}
      {:ok, _other_app1, after_it} -> app1(after_it)
      :truncated -> {:error, {:truncated, :app1}}
    end
  end

  defp app1(<<0xFF, _marker, length::16, rest::binary>>) do
    case segment(rest, length) do
      {:ok, _skipped, after_it} -> app1(after_it)
      :truncated -> {:error, {:truncated, :jpeg_segment}}
    end
  end

  defp app1(_neither_marker_nor_end), do: {:error, {:truncated, :jpeg_segment}}

  defp segment(rest, length) do
    size = max(length - 2, 0)

    case rest do
      <<segment::binary-size(size), after_it::binary>> -> {:ok, segment, after_it}
      _shorter -> :truncated
    end
  end

  # An IFD is a count and then twelve-byte entries: tag, type, count, and a four-byte
  # field holding the value where it fits and the offset to it where it does not.
  defp ifd(%{bytes: bytes, endian: endian}, offset, name) do
    with :ok <- reaches(bytes, offset, 2, name),
         count = read(bytes, offset, 16, endian),
         :ok <- reaches(bytes, offset + 2, count * 12, name) do
      {:ok,
       Map.new(0..(count - 1)//1, fn index ->
         at = offset + 2 + index * 12

         {read(bytes, at, 16, endian),
          %{
            type: read(bytes, at + 2, 16, endian),
            count: read(bytes, at + 4, 32, endian),
            field: binary_part(bytes, at + 8, 4)
          }}
       end)}
    end
  end

  defp value(%{bytes: bytes, endian: endian}, %{type: type, count: count, field: field}, name) do
    case Map.fetch(@sizes, type) do
      :error ->
        {:error, {:malformed, name}}

      {:ok, size} ->
        length = size * count

        with {:ok, data} <- data(bytes, field, length, endian, name) do
          decode(type, count, data, endian, name)
        end
    end
  end

  defp data(_bytes, field, length, _endian, _name) when length <= 4,
    do: {:ok, binary_part(field, 0, length)}

  defp data(bytes, field, length, endian, name) do
    offset = read(field, 0, 32, endian)

    with :ok <- reaches(bytes, offset, length, name) do
      {:ok, binary_part(bytes, offset, length)}
    end
  end

  # ASCII ends at its first NUL; SHORT and LONG are one number where there is one;
  # RATIONAL is pairs of LONGs.
  defp decode(2, _count, data, _endian, _name),
    do: {:ok, data |> :binary.split(<<0>>) |> hd()}

  defp decode(3, 1, data, endian, _name), do: {:ok, read(data, 0, 16, endian)}
  defp decode(4, 1, data, endian, _name), do: {:ok, read(data, 0, 32, endian)}

  defp decode(5, count, data, endian, _name) do
    {:ok,
     for index <- 0..(count - 1)//1 do
       {read(data, index * 8, 32, endian), read(data, index * 8 + 4, 32, endian)}
     end}
  end

  defp decode(_type, _count, _data, _endian, name), do: {:error, {:malformed, name}}

  defp reaches(bytes, offset, length, name) do
    if offset + length <= byte_size(bytes), do: :ok, else: {:error, {:truncated, name}}
  end

  defp read(binary, at, 16, :big),
    do: binary |> binary_part(at, 2) |> then(fn <<v::big-16>> -> v end)

  defp read(binary, at, 16, :little),
    do: binary |> binary_part(at, 2) |> then(fn <<v::little-16>> -> v end)

  defp read(binary, at, 32, :big),
    do: binary |> binary_part(at, 4) |> then(fn <<v::big-32>> -> v end)

  defp read(binary, at, 32, :little),
    do: binary |> binary_part(at, 4) |> then(fn <<v::little-32>> -> v end)
end
