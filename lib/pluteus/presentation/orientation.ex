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

  alias Pluteus.Exif

  @doc """
  How much of a file's head carries the orientation, where one is stated.
  """
  @spec head_bytes() :: pos_integer()
  def head_bytes, do: Exif.head_bytes()

  @doc """
  The orientation these bytes state, from 1 to 8, or nil where they state none or state
  one that cannot be read.
  """
  @spec of(binary()) :: 1..8 | nil
  def of(bytes) when is_binary(bytes) do
    case Exif.orientation(bytes) do
      {:ok, stated} -> stated
      :none -> nil
      {:error, _unreadable} -> nil
    end
  end

  @doc """
  Whether applying an orientation exchanges an image's width and height.

  Five through eight are the quarter turns and their mirrors; one through four leave
  the axes where they are.
  """
  @spec turns?(1..8 | nil) :: boolean()
  def turns?(orientation), do: orientation in 5..8
end
