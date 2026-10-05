defmodule Mix.Tasks.Fonts.Vendor do
  @shortdoc "Vendors, instances and subsets the self-hosted faces into priv"

  @moduledoc """
  Downloads each face `Pluteus.Design.Faces` pins, instances away every axis a CSS
  property cannot reach, subsets it to the coverage the household holds, writes it as
  woff2 under `priv/fonts/`, and records each file's upstream URL, SHA-256, axis ranges,
  vertical metrics and the advances A.3.4's measure is counted from in `SOURCES.json`.

  A.3.5 self-hosts the faces and makes subsetting the larger saving, so the vendored file
  is the subset rather than the whole face. The manifest exists because the emitted
  stylesheet's `font-weight` range, optical-size range and fallback metric overrides are
  read from what the face declares rather than typed by anybody — a figure in the CSS that
  disagrees with the file would be a layout nobody could explain.

  The licence travels with the copies, as A.8.1 requires of the glyph set: each face's own
  licence file is vendored beside it and `PluteusWeb.Notices` states it.

  The task rebuilds the directory from nothing, so it removes it before writing. What it
  wrote is committed; the digests are what a test then checks offline.

      docker compose run --rm app mix fonts.vendor
  """

  use Mix.Task

  alias Pluteus.Design.Faces

  @agent ~c"pluteus-fonts-vendor/0.1"

  # A.3.4's character count depends on the text it is counted over, so the count is taken
  # over a sample rather than modelled from a mean word length. The sample is A.3.4's own
  # normative sentence: prose of the kind the measure serves, held in the repository, and
  # auditable against the section it governs. A character outside the vendored subset
  # raises here rather than being skipped.
  @sample "Long-form text is constrained by a measure in ch, adjustable by the reader."

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _started} = Application.ensure_all_started([:inets, :ssl])

    root = Faces.root()
    File.rm_rf!(root)
    File.mkdir_p!(root)

    vendored = Enum.map(Faces.all(), &vendor!(&1, root))

    File.write!(
      Path.join(root, "SOURCES.json"),
      [Jason.encode_to_iodata!(%{"faces" => vendored}, pretty: true), "\n"]
    )

    Mix.shell().info("Vendored #{length(vendored)} faces into #{root}")
  end

  defp vendor!(face, root) do
    base = "https://raw.githubusercontent.com/#{face.repository}/#{face.version}/"

    Mix.shell().info("#{face.family} #{face.version}")

    whole = Path.join(System.tmp_dir!(), "#{face.id}-whole.ttf")
    pinned = Path.join(System.tmp_dir!(), "#{face.id}-pinned.ttf")
    target = Path.join(root, Faces.file(face))

    download!(base <> encode(face.source), whole)
    licence = vendor_licence!(face, base, root)

    instance!(whole, pinned, face)
    subset!(pinned, target, face)

    declared = declared!(target)
    body = File.read!(target)

    Mix.shell().info(
      "  #{Faces.file(face)} #{byte_size(body)} bytes, " <>
        "from #{File.stat!(whole).size} (#{saving(whole, body)})"
    )

    File.rm_rf!(whole)
    File.rm_rf!(pinned)

    %{
      "id" => face.id,
      "family" => face.family,
      "role" => face.role,
      "file" => Faces.file(face),
      "served" => Faces.served(face),
      "url" => base <> face.source,
      "version" => face.version,
      "licence" => licence,
      "licence_name" => face.licence_name,
      "bytes" => byte_size(body),
      "sha256" => sha256(body),
      "axes" => declared["axes"],
      "metrics" => declared["metrics"],
      "advances" => declared["advances"]
    }
  end

  defp vendor_licence!(face, base, root) do
    name = Faces.licence_file(face)
    target = Path.join(root, name)

    download!(base <> encode(face.licence), target)

    %{"file" => name, "url" => base <> face.licence, "sha256" => sha256(File.read!(target))}
  end

  # Every axis but the ones a CSS property reaches is pinned at its default, which is what
  # A.3.5's prohibition on raw variation settings implies: an axis no property can set is
  # an axis a utility would reset by accident, and carrying it costs bytes for a value
  # nothing chooses.
  #
  # The timestamp is not recalculated, which `TTFont.save` does by default. With it the
  # vendored bytes differ on every run and the recorded digest attests only that a file
  # was written; without it the same upstream at the same version yields the same bytes,
  # so a digest that fails to reproduce means the upstream moved.
  defp instance!(source, target, face) do
    python!("""
    from fontTools.ttLib import TTFont
    from fontTools.varLib import instancer

    font = TTFont(#{literal(source)}, recalcTimestamp=False)
    keep = #{literal(face.keep)}

    pins = {
      axis.axisTag: axis.defaultValue
      for axis in font["fvar"].axes
      if axis.axisTag not in keep
    }

    instancer.instantiateVariableFont(font, pins, inplace=True, updateFontNames=False)
    font.save(#{literal(target)})
    """)
  end

  defp subset!(source, target, face) do
    {output, status} =
      System.cmd(
        "pyftsubset",
        [
          source,
          "--output-file=#{target}",
          "--flavor=woff2",
          "--unicodes=#{face.subset}",
          "--layout-features=kern,liga,calt,tnum,frac",
          "--name-IDs=*",
          "--drop-tables+=DSIG",
          "--no-hinting"
        ],
        stderr_to_stdout: true
      )

    if status != 0, do: Mix.raise("pyftsubset refused #{face.family}: #{output}")
    unless File.exists?(target), do: Mix.raise("pyftsubset wrote no #{target}")
  end

  # Read back from the file that will actually be served, so the stylesheet's ranges are
  # the subset's own and not the whole face's.
  #
  # The advances are read for A.3.4, which fixes the measure at `55ch` and requires the
  # character count that yields be verified by counting when the face changes. `ch` is the
  # advance of the zero glyph, so the count follows from these three figures and the test
  # computes it: measuring here and asserting there is what makes re-vendoring re-verify.
  # They are read at the weight axis's default, which is what body text renders at.
  defp declared!(path) do
    python!("""
    import json
    from fontTools.ttLib import TTFont

    font = TTFont(#{literal(path)})
    head = font["head"]
    horizontal = font["hhea"]
    widths = font["hmtx"].metrics
    order = font.getBestCmap()

    axes = {
      axis.axisTag: {"min": axis.minValue, "default": axis.defaultValue, "max": axis.maxValue}
      for axis in font["fvar"].axes
    }

    metrics = {
      "units_per_em": head.unitsPerEm,
      "ascender": horizontal.ascender,
      "descender": horizontal.descender,
      "line_gap": horizontal.lineGap,
    }

    def advance(character):
      return widths[order[ord(character)]][0]

    sample = #{literal(@sample)}
    lowercase = [advance(chr(point)) for point in range(ord("a"), ord("z") + 1)]

    advances = {
      "zero": advance("0"),
      "lowercase_mean": sum(lowercase) / len(lowercase),
      "sample_characters": len(sample),
      "sample_advance": sum(advance(character) for character in sample),
    }

    print(json.dumps({"axes": axes, "metrics": metrics, "advances": advances}))
    """)
    |> Jason.decode!()
  end

  defp python!(script) do
    case System.cmd("python3", ["-c", script], stderr_to_stdout: true) do
      {output, 0} -> output
      {output, status} -> Mix.raise("python3 exited #{status}: #{output}")
    end
  end

  defp literal(value), do: Jason.encode!(value)

  defp saving(whole, body) do
    before = File.stat!(whole).size
    "#{Float.round(before / byte_size(body), 1)}x smaller"
  end

  # The source path carries the axis list in brackets, which a URL does not.
  defp encode(path), do: path |> String.replace("[", "%5B") |> String.replace("]", "%5D")

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
