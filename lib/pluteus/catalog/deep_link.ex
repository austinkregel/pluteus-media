defmodule Pluteus.Catalog.DeepLink do
  @moduledoc """
  Serializes an address onto an entity URI, and reads one back (§9).

  The query string carries the selector. §9.2 makes that REQUIRED: a fragment
  never reaches the server, so carrying the range there forecloses every
  server-side use of it — a link preview, a thumbnail at the linked moment,
  handing the range to a pipeline. The query form is a superset, since a client
  reads it just as readily.

  [MEDIA-FRAGS] supplies the `t` and `xywh` dimensions and the `&`-separated
  name-value grammar. Text position, text quote and page have no form there and
  use dimension names defined by this system in the same grammar.

  Two of that grammar's defaults are unusable here. A bare `xywh` is pixel
  coordinates, and `t` accepts an `smpte` basis counted in frames; §8.4 forbids
  both because neither survives a re-encode. A link carrying either is refused
  rather than reinterpreted.
  """

  alias Pluteus.Catalog.Address

  @paths %{
    "works" => :work,
    "expressions" => :expression,
    "manifestations" => :manifestation,
    "items" => :item,
    "digital-items" => :digital_item
  }

  @segments Map.new(@paths, fn {segment, kind} -> {kind, segment} end)

  @dimensions ~w(t xywh char word page quote prefix suffix)

  @order @dimensions

  @doc """
  The canonical link for an address.

  The result carries the selector in the query string and nothing in the
  fragment, which is the only form §9.2 permits this system to emit.
  """
  @spec build(Address.t()) :: String.t()
  def build(%Address{} = address) do
    segment = Map.fetch!(@segments, address.target_kind)
    query = address |> dimensions_of() |> encode()

    "/#{segment}/#{address.target_id}?#{query}"
  end

  @doc """
  Reads a deep link into the attributes an address is built from.

  A selector found in the fragment alone is moved to the query, since a link
  written against [MEDIA-FRAGS] elsewhere puts it there and the two forms carry
  the same information. A selector in both is refused: §9.2 forbids it outright,
  and the two may disagree, which leaves nothing to normalize toward.
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, term()}
  def parse(link) do
    uri = URI.parse(link)

    with {:ok, target_kind, target_id} <- target(uri.path),
         {:ok, dimensions, source} <- dimensions(uri),
         {:ok, selector} <- selector(dimensions),
         :ok <- valid_at_level(selector.selector_type, target_kind) do
      attrs = Map.merge(selector, %{target_id: target_id, target_kind: target_kind})

      {:ok, Map.merge(attrs, %{source: source, canonical: canonical(attrs)})}
    end
  end

  defp canonical(attrs) do
    "/#{Map.fetch!(@segments, attrs.target_kind)}/#{attrs.target_id}?#{encode(dimensions_of(struct(Address, attrs)))}"
  end

  defp target(nil), do: {:error, :no_entity_in_link}

  defp target(path) do
    case String.split(path, "/", trim: true) do
      [segment, id] ->
        with {:ok, kind} <- Map.fetch(@paths, segment) |> ok_or({:unknown_path, segment}),
             {:ok, _uuid} <- Ecto.UUID.cast(id) |> ok_or({:malformed_identifier, id}) do
          {:ok, kind, id}
        end

      _other ->
        {:error, {:unknown_path, path}}
    end
  end

  defp ok_or(:error, reason), do: {:error, reason}
  defp ok_or({:ok, value}, _reason), do: {:ok, value}

  # A fragment holding no dimension this system knows is left alone: §9.2
  # reserves the component for genuinely client-only use.
  defp dimensions(uri) do
    fragment = uri.fragment |> decode() |> Map.take(@dimensions)

    with {:ok, query} <- known(uri.query) do
      case {map_size(query), map_size(fragment)} do
        {0, 0} -> {:error, :no_selector}
        {_, 0} -> {:ok, query, :query}
        {0, _} -> {:ok, fragment, :fragment}
        {_, _} -> {:error, :selector_in_both_query_and_fragment}
      end
    end
  end

  defp decode(nil), do: %{}
  defp decode(string), do: URI.decode_query(string)

  defp known(query) do
    decoded = decode(query)

    case Enum.find(Map.keys(decoded), &(&1 not in @dimensions)) do
      nil -> {:ok, decoded}
      name -> {:error, {:unknown_dimension, name}}
    end
  end

  defp selector(dimensions) do
    dimensions
    |> Map.keys()
    |> Enum.sort()
    |> case do
      ["t"] -> temporal(dimensions)
      ["xywh"] -> spatial(dimensions)
      ["t", "xywh"] -> spatiotemporal(dimensions)
      ["char"] -> text_position(dimensions, "char", :character)
      ["word"] -> text_position(dimensions, "word", :word)
      ["page"] -> page(dimensions)
      names -> quote_or_unknown(dimensions, names)
    end
  end

  defp quote_or_unknown(dimensions, names) do
    if "quote" in names and Enum.all?(names, &(&1 in ~w(quote prefix suffix))) do
      {:ok,
       %{
         selector_type: :text_quote,
         quote_exact: dimensions["quote"],
         quote_prefix: dimensions["prefix"],
         quote_suffix: dimensions["suffix"]
       }}
    else
      {:error, {:no_selector_type_for, names}}
    end
  end

  defp temporal(dimensions) do
    with {:ok, start_ms, end_ms} <- time_range(dimensions["t"]) do
      {:ok, %{selector_type: :temporal, start_ms: start_ms, end_ms: end_ms}}
    end
  end

  defp spatial(dimensions) do
    with {:ok, region} <- region(dimensions["xywh"]) do
      {:ok, Map.put(region, :selector_type, :spatial)}
    end
  end

  defp spatiotemporal(dimensions) do
    with {:ok, start_ms, end_ms} <- time_range(dimensions["t"]),
         {:ok, region} <- region(dimensions["xywh"]) do
      {:ok,
       region
       |> Map.put(:selector_type, :spatiotemporal)
       |> Map.merge(%{start_ms: start_ms, end_ms: end_ms})}
    end
  end

  defp text_position(dimensions, name, unit) do
    with {:ok, [start_offset, end_offset]} <- integers(dimensions[name], 2, name) do
      {:ok,
       %{
         selector_type: :text_position,
         text_unit: unit,
         start_offset: start_offset,
         end_offset: end_offset
       }}
    end
  end

  defp page(dimensions) do
    with {:ok, [page_number]} <- integers(dimensions["page"], 1, "page") do
      {:ok, %{selector_type: :page, page_number: page_number}}
    end
  end

  # `npt` is the only basis [MEDIA-FRAGS] offers that §8.4 permits. `smpte` and
  # its variants count frames, and a framerate change moves every one of them.
  defp time_range("npt:" <> range), do: time_range(range)

  defp time_range(value) do
    case String.split(value, ":", parts: 2) do
      [basis, _rest] -> {:error, {:forbidden_basis, basis}}
      [range] -> npt_range(range)
    end
  end

  defp npt_range(range) do
    with [start_at, end_at] <- String.split(range, ","),
         {:ok, start_ms} <- milliseconds(start_at),
         {:ok, end_ms} <- milliseconds(end_at) do
      {:ok, start_ms, end_ms}
    else
      _no_range -> {:error, {:malformed_dimension, "t"}}
    end
  end

  defp milliseconds(seconds) do
    case Float.parse(seconds) do
      {value, ""} -> {:ok, round(value * 1000)}
      _not_a_number -> :error
    end
  end

  # A bare `xywh` is pixel coordinates in [MEDIA-FRAGS], and absolute pixels do
  # not survive a rescan at another resolution.
  defp region("percent:" <> values) do
    with {:ok, [x, y, width, height]} <- floats(values, 4, "xywh") do
      {:ok, %{x_percent: x, y_percent: y, width_percent: width, height_percent: height}}
    end
  end

  defp region(value) do
    case String.split(value, ":", parts: 2) do
      [basis, _rest] -> {:error, {:forbidden_basis, basis}}
      [_bare] -> {:error, {:forbidden_basis, "pixel"}}
    end
  end

  defp integers(value, count, name) do
    parsed = value |> String.split(",") |> Enum.map(&Integer.parse/1)

    if length(parsed) == count and Enum.all?(parsed, &match?({_number, ""}, &1)) do
      {:ok, Enum.map(parsed, fn {number, ""} -> number end)}
    else
      {:error, {:malformed_dimension, name}}
    end
  end

  defp floats(value, count, name) do
    parsed = value |> String.split(",") |> Enum.map(&Float.parse/1)

    if length(parsed) == count and Enum.all?(parsed, &match?({_number, ""}, &1)) do
      {:ok, Enum.map(parsed, fn {number, ""} -> number end)}
    else
      {:error, {:malformed_dimension, name}}
    end
  end

  defp valid_at_level(selector_type, target_kind) do
    if target_kind in Address.valid_levels(selector_type) do
      :ok
    else
      {:error, {:selector_invalid_at_level, selector_type, target_kind}}
    end
  end

  defp dimensions_of(%Address{selector_type: :temporal} = address), do: [time(address)]
  defp dimensions_of(%Address{selector_type: :spatial} = address), do: [xywh(address)]

  defp dimensions_of(%Address{selector_type: :spatiotemporal} = address) do
    [time(address), xywh(address)]
  end

  defp dimensions_of(%Address{selector_type: :text_position} = address) do
    name = if address.text_unit == :word, do: "word", else: "char"

    [{name, "#{address.start_offset},#{address.end_offset}"}]
  end

  defp dimensions_of(%Address{selector_type: :page} = address) do
    [{"page", Integer.to_string(address.page_number)}]
  end

  defp dimensions_of(%Address{selector_type: :text_quote} = address) do
    [
      {"quote", address.quote_exact},
      {"prefix", address.quote_prefix},
      {"suffix", address.quote_suffix}
    ]
    |> Enum.reject(fn {_name, value} -> is_nil(value) end)
  end

  defp time(address) do
    {"t", "#{seconds(address.start_ms)},#{seconds(address.end_ms)}"}
  end

  defp xywh(address) do
    values =
      Enum.map_join(
        [address.x_percent, address.y_percent, address.width_percent, address.height_percent],
        ",",
        &percent/1
      )

    {"xywh", "percent:#{values}"}
  end

  defp seconds(milliseconds) do
    whole = div(milliseconds, 1000)

    case rem(milliseconds, 1000) do
      0 ->
        Integer.to_string(whole)

      remainder ->
        fraction =
          remainder
          |> Integer.to_string()
          |> String.pad_leading(3, "0")
          |> String.trim_trailing("0")

        "#{whole}.#{fraction}"
    end
  end

  defp percent(value) do
    if value == Float.round(value) do
      value |> trunc() |> Integer.to_string()
    else
      Float.to_string(value)
    end
  end

  defp encode(dimensions) do
    dimensions
    |> Enum.sort_by(fn {name, _value} -> Enum.find_index(@order, &(&1 == name)) end)
    |> Enum.map_join("&", fn {name, value} -> "#{name}=#{escape(name, value)}" end)
  end

  # The quote dimensions carry arbitrary text; the rest are digits, commas and
  # the one colon that names the basis, all legal in a query unescaped.
  defp escape(name, value) when name in ~w(quote prefix suffix) do
    URI.encode_www_form(value)
  end

  defp escape(_name, value), do: value
end
