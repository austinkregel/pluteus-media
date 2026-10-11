defmodule Pluteus.Storage.NotMountedError do
  @moduledoc """
  Raised when a root this deployment writes under is not the volume it should be.
  """
  defexception [:message]
end

defmodule Pluteus.Storage.Mount do
  @moduledoc """
  Whether the volumes holding the household's bytes are actually mounted.

  An absent mount is not an absent directory. A mount point left unmounted is an
  ordinary empty directory on whatever disk it sits on, and every write primitive here
  makes its parents before writing — so an acquisition against an unmounted primary
  storage succeeds, puts the bytes on the local disk, and records a location. When the
  volume comes back it covers them: the catalog names assets whose bytes nothing can
  reach, and the disk that was never meant to hold them has filled.

  Reading fails the other way. An asset whose bytes are not where the record says is
  what spec-03's verification calls unreadable, so a pass run against an unmounted root
  would record that of every asset at once — a finding about the household's files that
  is really a finding about a cable.

  Neither is detectable afterwards from the catalog alone, which is why this is checked
  before the application starts rather than recovered from later.

  ## Why a file and not a directory

  A directory is what an unmounted mount point already is. The deployment places a
  regular file under each root by hand; its presence is the volume's own, because
  nothing but that volume carries it. A directory of the same name could be made by any
  process that got there first, including this one.

  Nothing reads what the file holds. It is evidence of a mount and not a record.

  ## The inbox does not acquire it

  An inbox is walked for anything a household dropped there, and acquisition *moves*
  what it takes. So the sentinel under the inbox is a file in the inbox, and the first
  pass carried it into primary storage as a holding and removed it from where it stood —
  after which nothing would start. `.pluteus` is in the ingest registry's ignored
  directories for that reason, beside the operating systems' own.
  """

  alias Pluteus.Storage
  alias Pluteus.Storage.NotMountedError

  @sentinel ".pluteus/mount-check"

  @doc """
  The path, relative to a root, that stands for that root being mounted.
  """
  @spec sentinel() :: String.t()
  def sentinel, do: @sentinel

  @doc """
  Each root whose absence this deployment cannot survive, with what to call it.

  The inbox is here beside primary storage because an unmounted inbox is a pass that
  reports it found nothing, which is also what a healthy empty inbox reports.
  """
  @spec roots() :: [{String.t(), Path.t()}]
  def roots do
    [
      {"primary storage", Storage.root()},
      {"the inbox", inbox()}
    ]
  end

  @doc """
  Raises unless every root carries its sentinel.
  """
  @spec ensure!() :: :ok
  def ensure! do
    Enum.each(roots(), fn {name, root} -> ensure!(name, root) end)
  end

  defp ensure!(name, root) do
    path = Path.join(root, @sentinel)

    if File.regular?(path) do
      :ok
    else
      raise NotMountedError, """
      #{name} is not mounted.

      #{root} does not carry #{@sentinel}, so it is either the wrong directory or a \
      mount point whose volume is absent. Nothing has been read or written.

      Where the volume is simply late, this will pass once it is mounted. Where the \
      directory is right and the file was never placed, create it.\
      """
    end
  end

  @doc """
  Places the sentinel under every root.

  For a root this deployment owns outright rather than mounts — a development tree, the
  directories a test run works in. A mounted volume's sentinel is placed by hand, since
  a deployment that could write its own would answer the question by asking itself.
  """
  @spec mark!() :: :ok
  def mark! do
    Enum.each(roots(), fn {_name, root} ->
      path = Path.join(root, @sentinel)

      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "This file is how Pluteus knows the volume under it is mounted.\n")
    end)
  end

  defp inbox do
    :pluteus
    |> Application.fetch_env!(Pluteus.Ingest)
    |> Keyword.fetch!(:inbox)
  end
end
