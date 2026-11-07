defmodule Pluteus.Id3 do
  @moduledoc """
  Reads the frames of an MP3's leading ID3v2 tag, versions 2.2, 2.3 and 2.4 ([ID3v2.2],
  [ID3v2.3], [ID3v2.4]).

  ffprobe passes a tag's text frames on as tags, and leaves out the binary ones. The one
  that matters here is `UFID`, where a tagger keeps the identifier it gave the recording:
  Picard writes the MusicBrainz recording identifier there and nowhere else, under the
  owner `http://musicbrainz.org` (spec-05 §9.1). `TSRC`, the ISRC, is read here too, so
  that an MP3's identifiers are read from the frames that carry them whatever ffprobe
  names them.

  **Absent and unreadable are different answers.** A file with no ID3v2 tag at its head
  states nothing: `:none`. A tag that is there and cannot be read is `{:error, why}`.

  **Only what the format defines exactly is read.** Unsynchronisation — over the whole tag
  in 2.2 and 2.3, frame by frame in 2.4 — is undone, and a 2.4 frame's data length
  indicator is stepped over. A frame that is compressed, encrypted or carries a group
  identifier is listed as `:unsupported` rather than decoded, and asking for one is an
  error naming it, so a frame this module cannot read is never mistaken for one the tag
  does not carry. A 2.2 tag marked compressed is unsupported as a whole, as its document
  directs a reader to ignore one.

  A 2.2 tag names its frames with three characters, and the frames asked for here are
  found under either name: `UFI` for `UFID`, `TRC` for `TSRC`.

  **A frame is listed under the identifier it carries.** The format allows capital letters
  and digits, and taggers write others — `Date` is one found in the wild — while giving the
  frame a size that reads correctly. Such a frame is listed as it is, since its
  identifier does not affect where the next frame begins. One whose identifier is not
  printable text at all means the frames are no longer being read where they begin, and
  is an error.

  An appended tag, after the audio and marked by a footer, is not read: the tag is read
  from the head of the file, where taggers put it.
  """

  import Bitwise

  @header_bytes 10

  # The 2.2 names of the frames this module is asked for.
  @three_character %{"UFID" => "UFI", "TSRC" => "TRC"}

  @typedoc "One frame: its identifier, and its body, or why its body is not read."
  @type frame :: {String.t(), binary() | :unsupported}

  @typedoc "Why a tag that is present cannot be read."
  @type unreadable ::
          {:unsupported_version, non_neg_integer()}
          | {:truncated, atom()}
          | {:malformed, atom()}
          | {:unsupported, String.t()}

  @doc """
  How many bytes from the head of a file the leading tag occupies, read from the tag's
  first ten bytes: what to read before `frames/1` can read the whole of it.
  """
  @spec tag_bytes(binary()) :: {:ok, pos_integer()} | :none | {:error, unreadable()}
  def tag_bytes(<<"ID3", _major, _revision, _flags, size::binary-4, _rest::binary>>) do
    with {:ok, size} <- synchsafe(size, :tag_size), do: {:ok, @header_bytes + size}
  end

  def tag_bytes(_no_tag), do: :none

  @doc """
  The frames of the tag these bytes begin with, in the order the tag holds them.
  """
  @spec frames(binary()) :: {:ok, [frame()]} | :none | {:error, unreadable()}
  def frames(<<"ID3", major, _revision, flags, size::binary-4, rest::binary>>)
      when major in [3, 4] do
    with {:ok, size} <- synchsafe(size, :tag_size),
         {:ok, body} <- exactly(rest, size, :tag) do
      unsynchronised = (flags &&& 0x80) != 0
      extended = (flags &&& 0x40) != 0
      body = if major == 3 and unsynchronised, do: resynchronised(body), else: body

      with {:ok, frames} <- after_extended(body, major, extended) do
        read_frames(frames, major, unsynchronised, [])
      end
    end
  end

  def frames(<<"ID3", 2, _revision, flags, size::binary-4, rest::binary>>) do
    with {:ok, size} <- synchsafe(size, :tag_size),
         {:ok, body} <- exactly(rest, size, :tag) do
      cond do
        (flags &&& 0x40) != 0 -> {:error, {:unsupported, "compressed tag"}}
        (flags &&& 0x80) != 0 -> read_frames(resynchronised(body), 2, false, [])
        true -> read_frames(body, 2, false, [])
      end
    end
  end

  def frames(<<"ID3", major, _rest::binary>>), do: {:error, {:unsupported_version, major}}
  def frames(_no_tag), do: :none

  @doc """
  The identifiers the tag's `UFID` frames give under one owner, such as
  `"http://musicbrainz.org"`.
  """
  @spec unique_file_identifiers([frame()], String.t()) ::
          {:ok, [String.t()]} | {:error, unreadable()}
  def unique_file_identifiers(frames, owner) do
    with {:ok, bodies} <- bodies(frames, "UFID") do
      identifiers =
        for body <- bodies, [^owner, identifier] <- [:binary.split(body, <<0>>)] do
          identifier
        end

      {:ok, identifiers}
    end
  end

  @doc """
  The values of one text frame, such as `"TSRC"`, decoded to UTF-8. A 2.4 frame may hold
  several, separated by a null.
  """
  @spec text([frame()], String.t()) :: {:ok, [String.t()]} | {:error, unreadable()}
  def text(frames, id) do
    with {:ok, bodies} <- bodies(frames, id) do
      Enum.reduce_while(bodies, {:ok, []}, &decoded_into/2)
    end
  end

  defp decoded_into(body, {:ok, values}) do
    case decoded(body) do
      {:ok, decoded} -> {:cont, {:ok, values ++ decoded}}
      :error -> {:halt, {:error, {:malformed, :text}}}
    end
  end

  defp bodies(frames, id) do
    names = [id | List.wrap(@three_character[id])]
    matching = for {name, body} <- frames, name in names, do: body

    if :unsupported in matching,
      do: {:error, {:unsupported, id}},
      else: {:ok, matching}
  end

  # In 2.3 the extended header's size excludes its own four bytes; in 2.4 it is synchsafe
  # and includes them.
  defp after_extended(body, _major, false), do: {:ok, body}

  defp after_extended(<<size::32, rest::binary>>, 3, true) do
    with {:ok, _extended} <- exactly(rest, size, :extended_header),
         do: {:ok, binary_part(rest, size, byte_size(rest) - size)}
  end

  defp after_extended(<<size::binary-4, _rest::binary>> = body, 4, true) do
    with {:ok, size} <- synchsafe(size, :extended_header),
         {:ok, _extended} <- exactly(body, size, :extended_header),
         do: {:ok, binary_part(body, size, byte_size(body) - size)}
  end

  defp after_extended(_short, _major, true), do: {:error, {:truncated, :extended_header}}

  # Frames end at the tag's end or where padding, which is zero bytes, begins.
  defp read_frames(<<>>, _major, _unsynchronised, read), do: {:ok, Enum.reverse(read)}

  defp read_frames(<<0, _padding::binary>>, _major, _unsynchronised, read),
    do: {:ok, Enum.reverse(read)}

  # A 2.2 frame is a three-character identifier and a three-byte size, with no flags.
  defp read_frames(<<id::binary-3, size::24, rest::binary>>, 2, sync, read) do
    with :ok <- frame_id(id),
         {:ok, body} <- exactly(rest, size, :frame) do
      read_frames(binary_part(rest, size, byte_size(rest) - size), 2, sync, [{id, body} | read])
    end
  end

  # The first flag byte is the frame's status — whether to keep it when the tag or file is
  # altered, and whether it is read-only — which says nothing about how to read it.
  defp read_frames(
         <<id::binary-4, size::binary-4, _status, format, rest::binary>>,
         major,
         sync,
         read
       )
       when major in [3, 4] do
    with :ok <- frame_id(id),
         {:ok, size} <- frame_size(size, major),
         {:ok, body} <- exactly(rest, size, :frame) do
      frame = {id, frame_body(body, major, format, sync)}
      read_frames(binary_part(rest, size, byte_size(rest) - size), major, sync, [frame | read])
    end
  end

  defp read_frames(_short, _major, _unsynchronised, _read), do: {:error, {:truncated, :frame}}

  defp frame_id(id) do
    if id =~ ~r/^[\x21-\x7E]+$/, do: :ok, else: {:error, {:malformed, :frame_id}}
  end

  # A 2.3 frame's size is a plain 32-bit integer; a 2.4 frame's is synchsafe.
  defp frame_size(<<size::32>>, 3), do: {:ok, size}
  defp frame_size(size, 4), do: synchsafe(size, :frame_size)

  # 2.3's second flag byte is %ijk00000 — compression, encryption, grouping; 2.4's is
  # %0h00kmnp — grouping, compression, encryption, unsynchronisation, data length
  # indicator.
  defp frame_body(body, 3, format, _sync) do
    if (format &&& 0xE0) != 0, do: :unsupported, else: body
  end

  defp frame_body(body, 4, format, tag_unsynchronised) do
    cond do
      (format &&& 0x4C) != 0 ->
        :unsupported

      (format &&& 0x01) != 0 ->
        frame_body(drop_length(body), 4, format &&& 0xFE, tag_unsynchronised)

      (format &&& 0x02) != 0 or tag_unsynchronised ->
        resynchronised(body)

      true ->
        body
    end
  end

  defp drop_length(<<_length::binary-4, data::binary>>), do: data
  defp drop_length(_short), do: :unsupported

  # Unsynchronisation inserts a zero byte after every $FF that could be read as the start
  # of a frame sync, and after every $FF already followed by one; removing the zero after
  # every $FF undoes both.
  defp resynchronised(:unsupported), do: :unsupported
  defp resynchronised(bytes), do: :binary.replace(bytes, <<0xFF, 0x00>>, <<0xFF>>, [:global])

  defp synchsafe(<<0::1, a::7, 0::1, b::7, 0::1, c::7, 0::1, d::7>>, _what),
    do: {:ok, a <<< 21 ||| b <<< 14 ||| c <<< 7 ||| d}

  defp synchsafe(_not_synchsafe, what), do: {:error, {:malformed, what}}

  defp exactly(bytes, size, _what) when byte_size(bytes) >= size,
    do: {:ok, binary_part(bytes, 0, size)}

  defp exactly(_bytes, _size, what), do: {:error, {:truncated, what}}

  # A text frame's first byte names its encoding: ISO-8859-1, UTF-16 with a byte order
  # mark, UTF-16 big-endian, or UTF-8 — the last two from 2.4.
  defp decoded(<<encoding, text::binary>>) when encoding in 0..3 do
    case :unicode.characters_to_binary(text, encoding(encoding, text), :utf8) do
      decoded when is_binary(decoded) ->
        {:ok,
         decoded
         |> String.trim_leading("﻿")
         |> String.split(<<0>>)
         |> Enum.map(&String.trim_leading(&1, "﻿"))
         |> Enum.reject(&(&1 == ""))}

      _invalid ->
        :error
    end
  end

  defp decoded(_unknown_encoding), do: :error

  defp encoding(0, _text), do: :latin1
  defp encoding(1, <<0xFF, 0xFE, _rest::binary>>), do: {:utf16, :little}
  defp encoding(1, _text), do: {:utf16, :big}
  defp encoding(2, _text), do: {:utf16, :big}
  defp encoding(3, _text), do: :utf8
end
