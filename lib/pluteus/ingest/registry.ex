defmodule Pluteus.Ingest.Registry do
  @moduledoc """
  The vocabularies ingest decides by (spec-01 §17): names an inbox never
  acquires, companion patterns, codec and format essence, the containers that
  hold a still image, category defaults, and the standard format per broad
  class.

  They are seed data, not specification, and ship as a file under `priv` that a
  release replaces. The file is read once and held for the life of the node.
  """

  @key {__MODULE__, :registry}

  @doc """
  Whether a path relative to the inbox names something that is never a holding:
  operating-system metadata, a download still in progress, or anything inside a
  directory that holds only such things.
  """
  @spec ignored?(String.t()) :: boolean()
  def ignored?(relative_path) do
    %{"names" => names, "prefixes" => prefixes, "suffixes" => suffixes, "directories" => dirs} =
      registry()["inbox_ignore"]

    segments = Path.split(relative_path)
    {directories, [file_name]} = Enum.split(segments, -1)

    Enum.any?(directories, &(&1 in dirs)) or file_name in names or
      String.starts_with?(file_name, prefixes) or String.ends_with?(file_name, suffixes)
  end

  @doc """
  The companion kind a file name matches, or nil (spec-04 §4.6).
  """
  @spec companion_kind(String.t()) :: String.t() | nil
  def companion_kind(file_name) do
    extension = file_name |> Path.extname() |> String.trim_leading(".") |> String.downcase()
    base_name = file_name |> Path.rootname() |> String.downcase()

    Enum.find_value(registry()["companions"], fn pattern ->
      matches_extension = extension in pattern["extensions"]
      matches_base = pattern["base_names"] == nil or base_name in pattern["base_names"]
      if matches_extension and matches_base, do: pattern["kind"]
    end)
  end

  @doc """
  The essence of one stream, from its codec and, for a codec with both modes,
  the probed parameter that tells them apart (spec-04 §5.2).
  """
  @spec stream_essence(map()) :: :lossy | :lossless | :unknown
  def stream_essence(%{"codec_name" => codec} = stream) do
    case Map.fetch(registry()["codecs"], codec) do
      {:ok, essence} when is_binary(essence) -> to_essence(essence)
      {:ok, %{"parameter" => parameter} = rule} -> by_parameter(rule, stream[parameter])
      :error -> by_prefix(codec)
    end
  end

  def stream_essence(_stream_without_codec), do: :unknown

  defp by_parameter(%{"cases" => cases} = rule, value) do
    case Map.fetch(cases, value) do
      {:ok, essence} -> to_essence(essence)
      :error when is_nil(value) -> :unknown
      :error -> rule |> Map.get("otherwise", "unknown") |> to_essence()
    end
  end

  defp by_prefix(codec) do
    Enum.find_value(registry()["codec_prefixes"], :unknown, fn {prefix, essence} ->
      if String.starts_with?(codec, prefix), do: to_essence(essence)
    end)
  end

  @doc """
  The class and essence of a format whose files carry no streams, or nil where
  the registry has no entry for it.
  """
  @spec streamless_format(String.t()) :: %{class: atom(), essence: atom()} | nil
  def streamless_format(format) do
    case registry()["streamless_formats"][format] do
      nil ->
        nil

      %{"class" => class, "essence" => essence} ->
        %{class: to_class(class), essence: to_essence(essence)}
    end
  end

  @doc """
  Whether a probed container holds a still image rather than moving pictures.
  """
  @spec image_container?(String.t() | nil) :: boolean()
  def image_container?(format_name), do: format_name in registry()["image_containers"]

  @doc """
  The category placement records where evidence decides nothing (spec-04 §6.3).
  """
  @spec default_category(atom(), String.t() | nil) :: String.t()
  def default_category(:companion, companion_kind),
    do: Map.fetch!(registry()["categories"]["companion"], companion_kind)

  def default_category(class, nil),
    do: Map.fetch!(registry()["categories"], Atom.to_string(class))

  @doc """
  The media type a format is served as, or `application/octet-stream` where the
  registry maps none (spec-07 §4.4).
  """
  @spec media_type(String.t()) :: String.t()
  def media_type(format),
    do: Map.get(registry()["media_types"], format, "application/octet-stream")

  @doc """
  The standard format a broad class is normalized into, or nil where the
  registry names none and a lossless acquisition is adopted as its own master.
  """
  @spec standard_format(atom()) :: map() | nil
  def standard_format(class), do: registry()["standard_formats"][Atom.to_string(class)]

  defp to_essence(essence) when essence in ~w(lossy lossless unknown not_applicable),
    do: String.to_existing_atom(essence)

  defp to_class(class) when class in ~w(companion audio video image text),
    do: String.to_existing_atom(class)

  defp registry do
    case :persistent_term.get(@key, nil) do
      nil ->
        loaded =
          :pluteus
          |> :code.priv_dir()
          |> Path.join("registries/ingest.json")
          |> File.read!()
          |> Jason.decode!()

        :persistent_term.put(@key, loaded)
        loaded

      loaded ->
        loaded
    end
  end
end
