defmodule Pluteus.Archive do
  @moduledoc """
  Lists what an archive holds and reads one entry out of it, with `bsdtar`
  (spec-04 §5.3, [spec-10] §12.1).

  Top-level rather than under `Pluteus.Ingest`, because both ends of the system need it:
  identification corroborates a comic archive from its entries, and §12.1's page reader
  extracts page *n* to make an image profile. The presentation layer must not reach into
  ingest to do that.

  **A container's bytes say nothing about what it holds.** A `.cbz` identifies as
  `x-fmt/263`, which is any ZIP, and a `.cbr` as `fmt/613`, which is any RAR. So the format
  cannot say a file is a comic, and mapping either to a class would make every archive in
  the house one. What the entries are is the only evidence there is.

  The entries are read by name, which is weaker than reading bytes and is what is
  available: identifying 200 entries by their content means extracting 200 files, and
  §4.5's prohibition is on consulting a *holding's* name for its own format rather than on
  reading the names an archive states about itself.

  This parses arbitrary bytes from the inbox in a child process of the application, as
  probing and identification do, so spec-04 §11 governs it. An archive from the inbox may
  declare any number of entries of any length, so `bsdtar`'s output is read through a port
  under a byte ceiling and a deadline, and the ceiling refuses it while it is still
  arriving rather than once it is all in memory.
  """

  alias Pluteus.Storage

  # Beyond this an archive is not a comic whatever its entries say, and reading further
  # buys nothing. The longest comic in a household is a few hundred pages.
  @entry_ceiling 5_000

  # One listing line is a path, and a path is bounded by the filesystem's own limit.
  @listing_ceiling 5_000 * 4_096

  # Long enough for a spinning disk to seek through a large archive's directory, short
  # enough that an archive crafted to make `bsdtar` wait does not hold the stage forever.
  @deadline 30_000

  @typedoc """
  Why an archive could not be read: it declares more than the ceiling admits, it holds an
  entry longer than the caller allowed, `bsdtar` refused it, or `bsdtar` did not finish.
  """
  @type refusal ::
          {:too_many, pos_integer()}
          | {:too_long, pos_integer()}
          | {:unreadable, non_neg_integer(), String.t()}
          | {:timed_out, pos_integer()}

  @doc """
  The names an archive holds, excluding the directories it declares.

  A directory is not an entry anyone can read: the owner's own `.cbz` holds `images/`
  alongside its pages, and counting it would make a 200-page comic 201 pages long.
  """
  @spec entries(String.t()) :: {:ok, [String.t()]} | {:error, refusal()}
  def entries(location) do
    case bounded(["-tf", Storage.path(location)], @listing_ceiling) do
      {:ok, output} -> named(output)
      {:error, _refusal} = refusal -> refusal
    end
  end

  defp named(output) do
    names =
      output
      |> String.split("\n", trim: true)
      |> Enum.reject(&String.ends_with?(&1, "/"))

    if length(names) > @entry_ceiling,
      do: {:error, {:too_many, @entry_ceiling}},
      else: {:ok, names}
  end

  @doc """
  The bytes of one entry, refused where it is longer than `limit`.

  The limit is the caller's because what is too long depends on what the entry is for: a
  metadata document that will be parsed is a few kilobytes, and a page that will be
  re-encoded is megabytes. An entry that exceeds it is refused rather than truncated,
  since half a document is not a document.
  """
  @spec read(String.t(), String.t(), pos_integer()) :: {:ok, binary()} | {:error, refusal()}
  def read(location, entry, limit) do
    bounded(["-xOf", Storage.path(location), entry], limit)
  end

  @doc """
  The most entries an archive may hold and still be read.
  """
  @spec entry_ceiling() :: pos_integer()
  def entry_ceiling, do: @entry_ceiling

  defp bounded(args, limit) do
    port =
      Port.open({:spawn_executable, bsdtar!()}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:args, args}
      ])

    deadline = System.monotonic_time(:millisecond) + @deadline

    gather(port, limit, deadline, [], 0)
  end

  defp gather(port, limit, deadline, chunks, read) do
    remaining = deadline - System.monotonic_time(:millisecond)

    receive do
      {^port, {:data, chunk}} ->
        read = read + byte_size(chunk)

        if read > limit do
          stop(port)
          {:error, {:too_long, limit}}
        else
          gather(port, limit, deadline, [chunk | chunks], read)
        end

      {^port, {:exit_status, 0}} ->
        {:ok, joined(chunks)}

      {^port, {:exit_status, status}} ->
        {:error, {:unreadable, status, chunks |> joined() |> String.trim()}}
    after
      max(remaining, 0) ->
        stop(port)
        {:error, {:timed_out, @deadline}}
    end
  end

  defp joined(chunks), do: chunks |> Enum.reverse() |> IO.iodata_to_binary()

  # Abandoning a port leaves whatever it had already written queued in this process's
  # mailbox, where the next `receive` in the stage would read it, so the close is followed
  # by a flush of everything still addressed from it.
  #
  # `bsdtar` may exit between the decision to abandon it and the close, and closing a port
  # that has closed itself raises.
  defp stop(port) do
    try do
      Port.close(port)
    catch
      :error, :badarg -> :ok
    end

    flush(port)
  end

  defp flush(port) do
    receive do
      {^port, _written} -> flush(port)
    after
      0 -> :ok
    end
  end

  defp bsdtar! do
    System.find_executable("bsdtar") ||
      raise "the bsdtar executable is not on the PATH; reading an archive needs libarchive"
  end
end
