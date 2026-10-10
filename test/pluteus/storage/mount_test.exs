defmodule Pluteus.Storage.MountTest do
  @moduledoc """
  The precondition the application starts behind: every root the household's bytes go
  under is the volume it should be, and not a mount point whose volume is absent.
  """

  use ExUnit.Case, async: false

  alias Pluteus.Storage.Mount
  alias Pluteus.Storage.NotMountedError

  setup do
    held = Enum.map(Mount.roots(), fn {_name, root} -> {root, sentinel_of(root)} end)

    on_exit(fn ->
      for {root, bytes} <- held do
        path = Path.join(root, Mount.sentinel())

        # Cleared first whatever is there: one of these tests leaves a directory at
        # the sentinel's path, and writing a file over a directory fails.
        File.rm_rf!(path)

        if bytes do
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, bytes)
        end
      end
    end)

    :ok
  end

  describe "A root is mounted when it carries the sentinel" do
    test "both roots carrying one passes" do
      assert Mount.ensure!() == :ok
    end

    test "a root missing it is refused, named, and nothing is written" do
      {name, root} = hd(Mount.roots())
      File.rm_rf!(Path.join(root, Mount.sentinel()))

      error = assert_raise NotMountedError, fn -> Mount.ensure!() end

      assert error.message =~ name
      assert error.message =~ root
      assert error.message =~ "Nothing has been read or written"
    end

    # The case the check exists for. An unmounted mount point is an ordinary empty
    # directory, so a check for the directory would pass exactly when it must not.
    test "a directory where the file should be does not count as mounted" do
      {_name, root} = hd(Mount.roots())
      path = Path.join(root, Mount.sentinel())

      File.rm_rf!(path)
      File.mkdir_p!(path)

      assert File.exists?(path)
      assert_raise NotMountedError, fn -> Mount.ensure!() end
    end

    test "an empty root is refused, which is what an absent volume looks like" do
      empty =
        Path.join(System.tmp_dir!(), "pluteus-unmounted-#{System.unique_integer([:positive])}")

      File.mkdir_p!(empty)
      on_exit(fn -> File.rm_rf!(empty) end)

      assert File.dir?(empty)
      refute File.regular?(Path.join(empty, Mount.sentinel()))
    end
  end

  describe "Marking a root this deployment owns" do
    test "writes a regular file under every root, which the check then accepts" do
      for {_name, root} <- Mount.roots() do
        File.rm_rf!(Path.join(root, Mount.sentinel()))
      end

      assert Mount.mark!() == :ok

      for {_name, root} <- Mount.roots() do
        assert File.regular?(Path.join(root, Mount.sentinel()))
      end

      assert Mount.ensure!() == :ok
    end
  end

  describe "The roots this deployment cannot survive the absence of" do
    test "are primary storage and the inbox, each named" do
      assert [{"primary storage", _}, {"the inbox", _}] = Mount.roots()
    end

    test "are distinct directories, so one standing in for the other cannot pass" do
      [{_, storage}, {_, inbox}] = Mount.roots()

      refute storage == inbox
    end
  end

  defp sentinel_of(root) do
    case File.read(Path.join(root, Mount.sentinel())) do
      {:ok, bytes} -> bytes
      {:error, _absent} -> nil
    end
  end
end
