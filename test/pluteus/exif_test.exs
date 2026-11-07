defmodule Pluteus.ExifTest do
  @moduledoc """
  What a still image's EXIF states about where it was taken (spec-05 §9.7), and the
  difference between an image that states nothing and one whose statement was lost.
  """

  use ExUnit.Case, async: true

  import Pluteus.IngestFixtures

  alias Pluteus.Exif

  # 42° 57' 48.24" N, 85° 40' 5.16" W, as a camera writes it: three rationals and a
  # reference letter each.
  @latitude [{0x0001, :ascii, "N"}, {0x0002, :rational, [{42, 1}, {57, 1}, {4824, 100}]}]
  @longitude [{0x0003, :ascii, "W"}, {0x0004, :rational, [{85, 1}, {40, 1}, {516, 100}]}]
  @accuracy [{0x001F, :rational, [{5, 1}]}]

  defp near({expected_latitude, expected_longitude}, %{latitude: latitude, longitude: longitude}) do
    abs(latitude - expected_latitude) < 1.0e-6 and abs(longitude - expected_longitude) < 1.0e-6
  end

  @here {42 + 57 / 60 + 48.24 / 3600, -(85 + 40 / 60 + 5.16 / 3600)}

  describe "§9.7. EXIF GPS is a position" do
    test "degrees, minutes and seconds, signed by their references, in either byte order" do
      for endian <- [:big, :little] do
        assert {:ok, position} =
                 Exif.position(located_jpeg(@latitude ++ @longitude ++ @accuracy, endian))

        assert near(@here, position), "#{endian}-endian read #{inspect(position)}"
        assert position.accuracy == 5.0
      end
    end

    test "south and east are the negative latitude and the positive longitude" do
      south_east = [
        {0x0001, :ascii, "S"},
        {0x0002, :rational, [{33, 1}, {52, 1}, {0, 1}]},
        {0x0003, :ascii, "E"},
        {0x0004, :rational, [{151, 1}, {12, 1}, {0, 1}]}
      ]

      assert {:ok, position} = Exif.position(located_jpeg(south_east))
      assert near({-(33 + 52 / 60), 151 + 12 / 60}, position)
    end

    test "a position whose device stated no error has no accuracy" do
      assert {:ok, %{accuracy: nil}} = Exif.position(located_jpeg(@latitude ++ @longitude))
    end

    test "a measurement the device marked active is read" do
      active = [{0x0009, :ascii, "A"} | @latitude ++ @longitude]
      assert {:ok, _position} = Exif.position(located_jpeg(active))
    end
  end

  describe "§9.7. An image stating no position states nothing" do
    test "no EXIF at all" do
      assert Exif.position(media!(:jpeg)) == :none
      assert Exif.position(media!(:png)) == :none
      assert Exif.position("not an image at all") == :none
    end

    test "EXIF with no GPS block" do
      assert Exif.position(oriented_jpeg(6)) == :none
    end

    test "a GPS block holding no coordinate" do
      assert Exif.position(located_jpeg([{0x0000, :long, 0x02030000}])) == :none
    end

    test "a measurement the device marked void" do
      # GPSStatus V: the receiver had no fix, and whatever coordinate follows is not one.
      void = [{0x0009, :ascii, "V"} | @latitude ++ @longitude]
      assert Exif.position(located_jpeg(void)) == :none
    end
  end

  describe "§9.7. A position that was written and cannot be read is an error, not a silence" do
    test "a latitude with no reference does not say which hemisphere" do
      unreferenced = [{0x0002, :rational, [{42, 1}, {57, 1}, {0, 1}]} | @longitude]
      assert Exif.position(located_jpeg(unreferenced)) == {:error, {:malformed, :latitude}}
    end

    test "a latitude with no longitude" do
      assert Exif.position(located_jpeg(@latitude)) == {:error, {:malformed, :longitude}}
    end

    test "a zero denominator" do
      zero = [{0x0001, :ascii, "N"}, {0x0002, :rational, [{42, 1}, {57, 0}, {0, 1}]} | @longitude]
      assert Exif.position(located_jpeg(zero)) == {:error, {:malformed, :latitude}}
    end

    test "a latitude beyond the pole" do
      beyond = [
        {0x0001, :ascii, "N"},
        {0x0002, :rational, [{95, 1}, {0, 1}, {0, 1}]} | @longitude
      ]

      assert Exif.position(located_jpeg(beyond)) == {:error, {:malformed, :latitude}}
    end

    test "a status that is neither active nor void" do
      odd = [{0x0009, :ascii, "Q"} | @latitude ++ @longitude]
      assert Exif.position(located_jpeg(odd)) == {:error, {:malformed, :gps_status}}
    end

    test "an APP1 segment cut short" do
      assert Exif.position(<<0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x40, "Exif", 0, 0>>) ==
               {:error, {:truncated, :app1}}
    end

    test "a block pointing past the bytes that were read" do
      # The GPS block's offset survives in IFD0 but the block itself is gone.
      <<0xFF, 0xD8, 0xFF, 0xE1, _length::16, "Exif", 0, 0, tiff::binary>> =
        located_jpeg(@latitude ++ @longitude)

      ifd0_only = binary_part(tiff, 0, 26)
      exif = "Exif" <> <<0, 0>> <> ifd0_only

      truncated = <<0xFF, 0xD8, 0xFF, 0xE1, byte_size(exif) + 2::16>> <> exif

      assert Exif.position(truncated) == {:error, {:truncated, :gps_ifd}}
    end
  end

  describe "the orientation, read by the same reader" do
    test "every stated value, and none where none is stated" do
      for orientation <- 1..8 do
        assert Exif.orientation(oriented_jpeg(orientation)) == {:ok, orientation}
      end

      assert Exif.orientation(media!(:jpeg)) == :none
      assert Exif.orientation(located_jpeg(@latitude ++ @longitude)) == :none
    end
  end
end
