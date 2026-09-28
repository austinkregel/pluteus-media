defmodule Mix.Tasks.Icons.Vendor do
  @shortdoc "Vendors the Heroicons drawings the interface names into priv"

  @moduledoc """
  Downloads the Heroicons drawings Annex A.8 names, at the version A.8.1 pins, and
  writes them under `priv/icons/heroicons/` with the licence and a `SOURCES.json`
  recording each file's URL and SHA-256.

  A.8.1 requires the set be "vendored into the repository. No external host, and no
  icon font." A dependency resolved by the build satisfies none of that: it is absent
  from a release, it is not in the tree a reader can see, and the licence obligation
  would travel with a checkout nobody committed.

  **The licence is why this is a task and not a copy.** Heroicons is MIT, Copyright
  (c) Tailwind Labs, Inc., and A.8.1 states the whole of the obligation: "The
  copyright notice and permission notice MUST travel with the vendored copies and with
  any glyph derived from them." The published `optimized` tree holds no `LICENSE` —
  the one thing the licence requires is the one thing a sparse checkout of it leaves
  out — so the file comes from the repository root at the pinned tag.

  ## Three grids, not one drawing scaled

  A.8.2 binds one variant to each size band, because the 20 and 16 drawings are
  separate artwork rather than the 24 reduced — which is what earns the set its place
  under A.3.5's requirement for an optical-size programme. Each glyph is vendored at
  all three so a surface can place it in any band without this task being re-run.

  `24/solid` is not vendored. A.8.2 reserves it for "a filled treatment at 24 px and
  above where the surrounding design calls for one" and nothing calls for one, so a
  template naming it fails to compile rather than reaching a drawing nobody chose.

  ## What the task checks

  Each drawing's opening tag is measured against A.8.1's own table — the viewBox for
  its grid, and the paint that grid is drawn with — and a mismatch raises. A.8.5 names
  the viewBox and the stroke width as properties a machine can check, and the
  component emits those attributes from the table rather than from the file, so a file
  that disagreed would render with attributes it was not drawn for.

  Raising the version is editing this task and re-running it: the new drawings and
  their digests arrive in one reviewable commit.

      docker compose run --rm app mix icons.vendor
  """

  use Mix.Task

  alias Pluteus.Design.Icons

  @agent ~c"pluteus-icons-vendor/0.1"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _started} = Application.ensure_all_started([:inets, :ssl])

    base = "https://raw.githubusercontent.com/tailwindlabs/heroicons/v#{Icons.version()}/"

    File.rm_rf!(Icons.root())
    File.mkdir_p!(Icons.root())

    licence = fetch!(base, "LICENSE")
    drawings = Enum.map(Icons.drawings(), &fetch_drawing!(base, &1))

    manifest = %{
      "tag" => "v#{Icons.version()}",
      "base" => base,
      "licence" => "MIT, Copyright (c) Tailwind Labs, Inc.",
      "inventory" => Icons.inventory(),
      "grids" => Icons.bands() |> Map.values() |> Enum.map(&elem(&1, 0)) |> Enum.sort(),
      "files" => Enum.sort_by([licence | drawings], & &1["path"])
    }

    File.write!(
      Path.join(Icons.root(), "SOURCES.json"),
      [Jason.encode_to_iodata!(manifest, pretty: true), "\n"]
    )

    Mix.shell().info(
      "Vendored #{length(drawings)} drawings of " <>
        "#{length(Icons.inventory())} glyphs into #{Icons.root()}"
    )
  end

  # A drawing is fetched to the path the component will read it from, so the vendored
  # tree and the compile-time read cannot disagree about where anything is.
  defp fetch_drawing!(base, {_name, target, grid}) do
    glyph = Path.basename(target, ".svg")
    fetch!(base, "optimized/#{grid}/#{glyph}.svg", grid)
  end

  # The path under the repository is the path under `priv`, less the `optimized/`
  # segment, so what is vendored reads as the grids A.8.1's table names.
  defp fetch!(base, path, grid \\ nil) do
    url = base <> path
    target = Path.join(Icons.root(), String.replace_prefix(path, "optimized/", ""))

    File.mkdir_p!(Path.dirname(target))
    download!(url, target)
    body = File.read!(target)

    if grid, do: drawn_as!(body, grid, path)
    Mix.shell().info("  #{path}")

    %{
      "path" => Path.relative_to(target, Icons.root()),
      "url" => url,
      "sha256" => sha256(body)
    }
  end

  # A.8.5: the viewBox and the stroke width are properties a machine can check, and
  # these are the ones the component emits from A.8.1's table. A drawing whose own tag
  # disagrees would be rendered with attributes it was not drawn for — a 16 grid under
  # a 24 viewBox is a glyph in the corner of an empty box — so the disagreement raises
  # here rather than reaching a screen.
  defp drawn_as!(body, grid, path) do
    {view_box, paint} = Map.fetch!(Icons.paint(), grid)
    [opening | _rest] = String.split(body, ">", parts: 2)
    expected = [{"viewBox", view_box} | paint]

    for {attribute, value} <- expected do
      unless String.contains?(opening, ~s(#{attribute}="#{value}")) do
        Mix.raise(
          "#{path} is not drawn as A.8.1 says #{grid} is: " <>
            ~s(it lacks #{attribute}="#{value}")
        )
      end
    end
  end

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
