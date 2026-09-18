defmodule Pluteus.DemoManifestTest do
  @moduledoc """
  The demo corpus manifest: every file is openly licensed, pinned by digest,
  credited, and says what it is there to show.
  """

  use ExUnit.Case, async: true

  alias Mix.Tasks.Pluteus.Demo.Seed

  @open_licences ["CC0", "CC0 1.0", "Public domain", "Public domain in the USA"]

  test "every entry is pinned, credited, openly licensed and has a purpose" do
    entries = Seed.manifest()

    assert [_ | _] = entries

    for entry <- entries do
      assert entry["licence"] in @open_licences, entry["path"]
      assert entry["sha256"] =~ ~r/\A[0-9a-f]{64}\z/, entry["path"]
      assert String.starts_with?(entry["url"], "https://"), entry["path"]
      assert String.starts_with?(entry["source"], "https://"), entry["path"]
      assert entry["credit"] not in [nil, ""], entry["path"]
      assert entry["demonstrates"] not in [nil, ""], entry["path"]
    end
  end

  test "no two entries land at one inbox path or share bytes" do
    entries = Seed.manifest()

    assert entries |> Enum.map(& &1["path"]) |> Enum.uniq() |> length() == length(entries)
    assert entries |> Enum.map(& &1["sha256"]) |> Enum.uniq() |> length() == length(entries)
  end
end
