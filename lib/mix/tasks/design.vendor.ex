defmodule Mix.Tasks.Design.Vendor do
  @shortdoc "Vendors the Design Tokens Format Module's JSON Schema tree into priv"

  @moduledoc """
  Downloads the JSON Schema for the Design Tokens Format Module version Annex A
  pins, and writes it under `priv/design/schemas/dtcg/<version>/` with a
  `SOURCES.json` recording each file's URL and SHA-256.

  A.1.1 requires the token file validate against the published schema for that
  version with no errors, and requires that validation run in continuous
  integration. CI has no business reaching the network for it: a schema fetched at
  test time makes a green run depend on somebody else's uptime, and a silently
  changed schema would change what the assertion means. So the tree is vendored,
  and `Pluteus.Design.Schema` refuses any reference that is not in it.

  **The published schema is one bundled file.** `format.json` inlines each of its
  seventeen sibling schemas into `definitions`, keyed by that sibling's URL and
  carrying its own `$id`, so a conforming resolver answers every remote `$ref` from
  inside the document. The sibling URLs themselves answer 404, which is not a
  defect: they were never meant to be fetched.

  So the task vendors the one file and then **proves** it is closed — every `$ref`
  that is not a local JSON pointer must be satisfied by an embedded `$id`, and one
  that is not raises. That is what makes "validation reaches no network" a checked
  claim rather than a hope, and it is how a future version that unbundles gets
  noticed here instead of in CI.

  A.1.1 also pins the version exactly, because "the format's only stated evolution
  mechanism is a superseding specification". Raising the version is editing this
  task and re-running it, which is the point: the new tree and its digests arrive
  in one reviewable commit.

  The task rebuilds the tree from nothing, so it removes the version's directory
  before writing. What it wrote is committed; the digests are what a test then
  checks offline.

      docker compose run --rm app mix design.vendor
  """

  use Mix.Task

  alias Pluteus.Design.Schema

  @format_version "2025.10"
  @base "https://www.designtokens.org/schemas/#{@format_version}/"
  @agent ~c"pluteus-design-vendor/0.1"

  # A.1.1 pins two documents at this version: the format, which the token file
  # validates against, and the Resolver Module, which A.1.1 requires contexts be
  # expressed with "as modifiers over a resolution order, not as separate files of
  # separate names". Both are published as bundled schemas at the same base.
  @entries %{"format" => "format.json", "resolver" => "resolver.json"}

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _started} = Application.ensure_all_started([:inets, :ssl])

    root = Schema.root(@format_version)
    File.rm_rf!(root)
    File.mkdir_p!(root)

    vendored = Enum.map(Map.values(@entries), &fetch!(&1, root))

    manifest = %{
      "format_version" => @format_version,
      "base" => @base,
      "entries" => @entries,
      "files" => Enum.sort_by(vendored, & &1["path"])
    }

    File.write!(
      Path.join(root, "SOURCES.json"),
      [Jason.encode_to_iodata!(manifest, pretty: true), "\n"]
    )

    Mix.shell().info("Vendored the #{@format_version} schema into #{root}")
  end

  defp fetch!(path, root) do
    url = @base <> path
    target = Path.join(root, path)

    File.mkdir_p!(Path.dirname(target))
    download!(url, target)
    body = File.read!(target)
    decoded = Jason.decode!(body)

    closed!(decoded, path)
    Mix.shell().info("  #{path}")

    %{"path" => path, "url" => url, "sha256" => sha256(body)}
  end

  # Every reference that is not a local JSON pointer must be answered from inside
  # the document, by a subschema whose own `$id` is that URL. One that is not means
  # the schema stopped being self-contained, and resolving it would need the network
  # that A.1.1's continuous integration must not depend on.
  defp closed!(decoded, path) do
    embedded = embedded_ids(decoded, MapSet.new())

    remote =
      decoded
      |> references([])
      |> Enum.reject(&String.starts_with?(&1, "#"))
      |> Enum.map(fn reference ->
        [addressed | _fragment] = String.split(reference, "#", parts: 2)
        addressed
      end)
      |> Enum.uniq()

    case Enum.reject(remote, &MapSet.member?(embedded, &1)) do
      [] ->
        Mix.shell().info("  #{path} answers its own #{length(remote)} remote references")

      [unanswered | _rest] ->
        Mix.raise("#{path} references #{unanswered}, which nothing in it declares an $id for")
    end
  end

  defp embedded_ids(%{} = map, found) do
    found = if is_binary(map["$id"]), do: MapSet.put(found, map["$id"]), else: found
    Enum.reduce(map, found, fn {_key, value}, found -> embedded_ids(value, found) end)
  end

  defp embedded_ids(list, found) when is_list(list),
    do: Enum.reduce(list, found, &embedded_ids/2)

  defp embedded_ids(_scalar, found), do: found

  defp references(%{} = map, found) do
    Enum.reduce(map, found, fn
      {"$ref", value}, found when is_binary(value) -> [value | found]
      {_key, value}, found -> references(value, found)
    end)
  end

  defp references(list, found) when is_list(list), do: Enum.reduce(list, found, &references/2)
  defp references(_scalar, found), do: found

  defp download!(url, destination) do
    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 4,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    request = {String.to_charlist(url), [{~c"user-agent", @agent}]}

    case :httpc.request(:get, request, [ssl: ssl, autoredirect: true],
           stream: String.to_charlist(destination)
         ) do
      {:ok, :saved_to_file} ->
        :ok

      {:ok, {{_version, status, _reason}, _headers, _body}} ->
        Mix.raise("#{url} answered #{status}")

      {:error, reason} ->
        Mix.raise("#{url} could not be fetched: #{inspect(reason)}")
    end
  end

  defp sha256(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
end
