defmodule Pluteus.Design.WatcherTest do
  @moduledoc """
  What makes a token value cheap to try, and the one thing that would quietly stop it
  being so.

  Annex A calls its values "starting values, maintained as spec-10 §20's registry", and
  A.10.1's whole consequence is that changing one needs no rebuild. That only holds if
  a change on disk reaches the stylesheet, and `Pluteus.Design.Tokens` holds each
  document in `:persistent_term` for the life of the node — so a rebuild that did not
  forget first would regenerate the values already in memory and write the stylesheet it
  already had, with nothing anywhere to say the edit had been ignored.

  These run against the real token file, so they restore it, and they are synchronous
  because the cache they clear is global.
  """

  use ExUnit.Case, async: false

  alias Pluteus.Design.Build
  alias Pluteus.Design.Tokens

  setup do
    original = File.read!(path())

    on_exit(fn ->
      File.write!(path(), original)
      Tokens.forget()
    end)

    # Warm the cache, which is the state a running node is always in.
    Tokens.resolve!("sys.color.surface.base")

    %{original: original}
  end

  describe "A value changed on disk reaches the stylesheet" do
    test "forgetting is what makes the next read see the edit", %{original: original} do
      before = Tokens.resolve!("base.grey.01")["hex"]

      File.write!(path(), String.replace(original, ~s("#101113"), ~s("#0d0e10")))

      assert Tokens.resolve!("base.grey.01")["hex"] == before,
             "the cache is what this test exists to be about; it did not hold the value"

      Tokens.forget()

      assert Tokens.resolve!("base.grey.01")["hex"] == "#0d0e10"
    end

    test "the rebuilt stylesheet carries the edited value", %{original: original} do
      refute Build.stylesheet() =~ "#0d0e10"

      File.write!(path(), String.replace(original, ~s("#101113"), ~s("#0d0e10")))
      Tokens.forget()

      css = Build.stylesheet()

      assert css =~ "--color-grey-01: #0d0e10;"
      refute css =~ "--color-grey-01: #101113;"
    end

    test "a context override is forgotten too, not only the default resolution" do
      # Each context is a document of its own under its own cache key, so forgetting one
      # and keeping the rest would rebuild a stylesheet that was half the edit.
      light = Path.join(Tokens.root(), "contexts/light.json")
      original = File.read!(light)
      on_exit(fn -> File.write!(light, original) end)

      Tokens.resolve!("base.grey.01", "light")
      File.write!(light, String.replace(original, ~s("#fcfcfd"), ~s("#fdfdfe")))
      Tokens.forget()

      assert Tokens.resolve!("base.grey.01", "light")["hex"] == "#fdfdfe"
    end
  end

  describe "The watcher runs where it can write and nowhere else" do
    test "it is off unless configured on" do
      # A release replaces `priv` rather than editing it underneath a running node, and
      # there is no `assets/` there to write into — so the default is off and dev turns
      # it on, rather than the module deciding for itself what environment it is in.
      refute Keyword.fetch!(Application.fetch_env!(:pluteus, Pluteus.Design.Watcher), :start)
    end
  end

  defp path, do: Path.join(Tokens.root(), "tokens.json")
end
