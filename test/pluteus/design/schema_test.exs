defmodule Pluteus.Design.SchemaTest do
  @moduledoc """
  Annex A.1.1: the token file validates against the published schema for the pinned
  version, with no errors, and that validation runs in continuous integration.

  This file asserts the schema half — that what is vendored is the pinned version,
  unmodified, and resolvable without reaching the network. What validates the token
  file against it lives with the token file.
  """

  use ExUnit.Case, async: true

  alias Pluteus.Design.Schema

  describe "A.1.1. The schema is the pinned version, vendored and unmodified" do
    test "the version is pinned exactly, and the file says so itself" do
      # A.1.1 pins the version exactly because "the format's only stated evolution
      # mechanism is a superseding specification", so the schema's own `$id` has to
      # agree with what the deployment thinks it vendored.
      assert Schema.format_version() == "2025.10"

      sources = Schema.sources()
      assert sources["format_version"] == "2025.10"
      assert sources["base"] == "https://www.designtokens.org/schemas/2025.10/"
      assert sources["entry"] == "format.json"

      schema = Schema.read!("format.json")
      assert schema["$id"] == "https://www.designtokens.org/schemas/2025.10/format.json"
      assert schema["$schema"] == "http://json-schema.org/draft-07/schema#"
    end

    test "every vendored file still has the digest it was fetched with" do
      for %{"path" => path, "sha256" => expected} <- Schema.sources()["files"] do
        actual =
          Schema.root()
          |> Path.join(path)
          |> File.read!()
          |> then(&:crypto.hash(:sha256, &1))
          |> Base.encode16(case: :lower)

        assert actual == expected, "#{path} is not the file SOURCES.json pins"
      end
    end

    test "it resolves, and reaches no network to do it" do
      # The published schema inlines its seventeen sibling schemas into
      # `definitions`, each under its own URL and carrying its own `$id`, so every
      # remote reference is answered from inside the document. Resolving with no
      # resolver hook is what proves it: a hook is where a fetch would hide.
      assert %ExJsonSchema.Schema.Root{} = Schema.resolved()
    end

    test "no reference escapes the document" do
      # The vendoring task checks this when it downloads. Asserting it again here is
      # what keeps it true of the committed file: a version that unbundles would
      # otherwise resolve by fetching, and a green run would depend on a web server.
      schema = Schema.read!("format.json")
      embedded = ids(schema, MapSet.new())

      remote =
        schema
        |> refs([])
        |> Enum.reject(&String.starts_with?(&1, "#"))
        |> Enum.map(&(&1 |> String.split("#", parts: 2) |> hd()))
        |> Enum.uniq()

      assert remote != [], "the schema is expected to carry remote references"
      assert Enum.reject(remote, &MapSet.member?(embedded, &1)) == []
    end

    test "it rejects a token file the format forbids" do
      # So that a passing validation means something. A group name may not contain a
      # dot, which is how the format keeps a name from colliding with a reference
      # path — the same reason A.1.5 rule 3 forbids one in a segment.
      root = Schema.resolved()

      assert :ok = ExJsonSchema.Validator.validate(root, %{"colour" => %{}})

      assert {:error, [_ | _]} =
               ExJsonSchema.Validator.validate(root, %{"sys.color" => %{}})
    end
  end

  defp refs(%{} = map, found) do
    Enum.reduce(map, found, fn
      {"$ref", value}, found when is_binary(value) -> [value | found]
      {_key, value}, found -> refs(value, found)
    end)
  end

  defp refs(list, found) when is_list(list), do: Enum.reduce(list, found, &refs/2)
  defp refs(_scalar, found), do: found

  defp ids(%{} = map, found) do
    found = if is_binary(map["$id"]), do: MapSet.put(found, map["$id"]), else: found
    Enum.reduce(map, found, fn {_key, value}, found -> ids(value, found) end)
  end

  defp ids(list, found) when is_list(list), do: Enum.reduce(list, found, &ids/2)
  defp ids(_scalar, found), do: found
end
