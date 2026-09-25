defmodule Pluteus.Presentation.Tiles do
  @moduledoc """
  A tiled pyramid for an image too large to serve whole ([spec-10] §11.2).

  Above §20's threshold a graded profile set stops being the right shape: a 600dpi A4
  scan is 34.8 megapixels, and the widest profile either throws away what the scan was
  made for or sends the whole thing to look at one corner. The pyramid is the answer,
  under the [IIIF-IMAGE] URL grammar so the client is off-the-shelf.

  **The pyramid is one file.** `vips dzsave` writes it as a zip whose entries are
  already IIIF paths — `{region}/{size}/{rotation}/default.jpg` — so a pyramid is one
  presentation asset with one location, and evicting it removes the whole thing rather
  than leaving a tree behind.

  **Regions are translated, never stored.** spec-01 §8.4 forbids a pixel region as an
  addressing basis because it does not survive a re-encode, and §11.2 permits a
  display-time crop against a named derivative only because that is not an addressing
  basis. So `pct/2` and `xywh/2` convert between the grammar's percentage form and the
  deep link's, and nothing here writes a pixel region anywhere.
  """

  alias Pluteus.Presentation.Registry
  alias Pluteus.Storage

  @doc """
  Whether an image is large enough that §20 asks for a pyramid rather than a profile.
  """
  @spec tiled?(pos_integer(), pos_integer()) :: boolean()
  def tiled?(width, height),
    do: width * height > Map.fetch!(Registry.tiling(), "threshold_pixels")

  @doc """
  Writes a pyramid of the image at `source` to `target`, as a zip.
  """
  @spec build(String.t(), String.t()) :: :ok | {:error, String.t(), map()}
  def build(source, target) do
    path = Storage.path(target)
    File.mkdir_p!(Path.dirname(path))

    tiling = Registry.tiling()

    args = [
      "dzsave",
      Storage.path(source),
      path,
      "--layout",
      "iiif3",
      "--tile-size",
      Integer.to_string(Map.fetch!(tiling, "tile_size")),
      "--suffix",
      ".jpg"
    ]

    case System.cmd("vips", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, "pyramid_not_built", %{status: status, output: output}}
    end
  end

  @doc """
  One entry of a pyramid, by the path the [IIIF-IMAGE] grammar names it with.

  `info.json` is rewritten as it is read, because `vips` writes a placeholder identifier
  and a client follows the one it is given: an information document naming somebody
  else's host is worse than none.
  """
  @spec entry(String.t(), String.t(), String.t()) ::
          {:ok, binary(), String.t()} | {:error, :no_such_tile}
  def entry(location, path, identifier) do
    archive = Storage.path(location)

    case :zip.extract(String.to_charlist(archive), [
           :memory,
           {:file_list, [String.to_charlist(inside(location, path))]}
         ]) do
      {:ok, [{_name, bytes}]} -> {:ok, rewritten(path, bytes, identifier), media_type(path)}
      _absent -> {:error, :no_such_tile}
    end
  end

  @doc """
  The information document a pyramid carries, with its identifier and the deployment's
  own compliance level.

  `vips` writes a level 0 pyramid: only the tile URLs it generated are addressable. The
  deployment serves the percentage region form on top of that, which IIIF declares as an
  extra feature rather than as a higher level, because the rest of level 1 is not
  offered and claiming it would be a promise to a client.
  """
  @spec information(String.t(), String.t()) :: {:ok, map()} | {:error, :no_such_tile}
  def information(location, identifier) do
    case entry(location, "info.json", identifier) do
      {:ok, bytes, _media_type} -> {:ok, Jason.decode!(bytes)}
      error -> error
    end
  end

  @doc """
  A region as the [IIIF-IMAGE] grammar spells it, from one as spec-01 §9.1's deep link
  spells it.

      iex> Pluteus.Presentation.Tiles.pct("percent:25,25,50,50")
      "pct:25.0,25.0,50.0,50.0"
  """
  @spec pct(String.t()) :: String.t() | :error
  def pct("percent:" <> numbers), do: as("pct:", numbers)
  def pct(_not_a_percentage_region), do: :error

  @doc """
  The same region, back the other way.

      iex> Pluteus.Presentation.Tiles.xywh("pct:25,25,50,50")
      "percent:25.0,25.0,50.0,50.0"
  """
  @spec xywh(String.t()) :: String.t() | :error
  def xywh("pct:" <> numbers), do: as("percent:", numbers)
  def xywh(_not_a_percentage_region), do: :error

  # A region is four numbers and nothing else, so the shape is matched rather than
  # counted: anything longer or shorter is not a region.
  defp as(prefix, numbers) do
    case numbers |> String.split(",") |> Enum.map(&Float.parse(String.trim(&1))) do
      [{_, ""}, {_, ""}, {_, ""}, {_, ""}] = parsed ->
        prefix <> Enum.map_join(parsed, ",", fn {value, _rest} -> to_string(value) end)

      _not_four_numbers ->
        :error
    end
  end

  # dzsave names the directory inside the archive after the file it wrote, so every
  # entry sits under the archive's own stem.
  defp inside(location, path), do: Path.join(stem(location), path)

  defp stem(location), do: location |> Path.basename() |> Path.rootname()

  defp rewritten("info.json", bytes, identifier) do
    bytes
    |> Jason.decode!()
    |> Map.put("id", identifier)
    |> Map.put("extraFeatures", ["regionByPct", "sizeByW"])
    |> Jason.encode!()
  end

  defp rewritten(_tile, bytes, _identifier), do: bytes

  defp media_type("info.json"), do: "application/json"
  defp media_type(_tile), do: "image/jpeg"
end
