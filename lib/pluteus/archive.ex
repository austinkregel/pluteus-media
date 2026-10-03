defmodule Pluteus.Archive do
  @moduledoc """
  Lists what an archive holds, with `bsdtar` (spec-04 §5.3, [spec-10] §12.1).

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
  probing and identification do. spec-04 §11 records what that exposes, and the entry
  count is bounded here because an archive declaring millions of entries costs one line of
  output each.
  """

  alias Pluteus.Storage

  # Beyond this an archive is not a comic whatever its entries say, and reading further
  # buys nothing. The longest comic in a household is a few hundred pages.
  @entry_ceiling 5_000

  @doc """
  The names an archive holds, excluding the directories it declares.

  A directory is not an entry anyone can read: the owner's own `.cbz` holds `images/`
  alongside its pages, and counting it would make a 200-page comic 201 pages long.
  """
  @spec entries(String.t()) ::
          {:ok, [String.t()]}
          | {:error, {:unreadable, non_neg_integer(), String.t()}}
          | {:error, {:too_many, pos_integer()}}
  def entries(location) do
    case System.cmd(bsdtar!(), ["-tf", Storage.path(location)], stderr_to_stdout: true) do
      {output, 0} -> named(output)
      {output, status} -> {:error, {:unreadable, status, String.trim(output)}}
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
  The most entries an archive may hold and still be read.
  """
  @spec entry_ceiling() :: pos_integer()
  def entry_ceiling, do: @entry_ceiling

  defp bsdtar! do
    System.find_executable("bsdtar") ||
      raise "the bsdtar executable is not on the PATH; reading an archive needs libarchive"
  end
end
