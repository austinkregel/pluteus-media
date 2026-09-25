defmodule Pluteus.Presentation.Registry do
  @moduledoc """
  The presentation profiles spec-10 §20 holds: the graded image widths, the
  aspect ratio a surface reserves before a probe has run, the tiling threshold,
  the trickplay and key-frame profiles, and the waveform resolutions.

  **The set of profile names is closed** (spec-10 §11.1). A surface asks for an
  artefact by name, and a request naming dimensions is refused, because an
  endpoint that accepts arbitrary width and height is an unbounded transcoder
  addressable by anyone who can construct a query string.

  A profile declares its own resolution, so a surface can tell what it is holding
  and MUST NOT offer a zoom finer than the stored artefact supports.
  """

  alias Pluteus.Registry

  @source "presentation"

  @doc """
  Every image profile, from the narrowest width to the widest.
  """
  @spec image_profiles() :: [map()]
  def image_profiles, do: Enum.sort_by(registry()["image_profiles"], & &1["width"])

  @doc """
  Every profile name the deployment serves, across all families.

  This is the closed set §11.1 names, and it is what a refusal lists.
  """
  @spec profile_names() :: [String.t()]
  def profile_names do
    Enum.map(image_profiles(), & &1["name"]) ++
      [placeholder_profile()["name"], trickplay()["name"], key_frame()["name"]] ++
      [waveform_overview()["name"]] ++
      Enum.map(waveform_detail(), & &1["name"]) ++
      Enum.map(text_profiles(), & &1["name"])
  end

  @doc """
  The profile a name refers to, or `:error` where the name is outside the closed
  set.
  """
  @spec profile(String.t()) :: {:ok, map()} | :error
  def profile(name) do
    all =
      image_profiles() ++
        [placeholder_profile(), trickplay(), key_frame(), waveform_overview()] ++
        waveform_detail() ++ text_profiles()

    case Enum.find(all, &(&1["name"] == name)) do
      nil -> :error
      found -> {:ok, found}
    end
  end

  @doc """
  The image profile an OpenSubsonic `size` maps to: the smallest whose width is
  at or above it (spec-07 §6.7, spec-10 §11.1).

  A request naming no size takes the default. A size above the widest profile
  takes the widest, and the response names what it served — the closed set is
  not widened by asking for more than it holds.
  """
  @spec image_profile_for_size(pos_integer() | nil) :: map()
  def image_profile_for_size(nil), do: default_image_profile()

  def image_profile_for_size(size) when is_integer(size) and size > 0 do
    profiles = image_profiles()

    Enum.find(profiles, List.last(profiles), &(&1["width"] >= size))
  end

  @spec default_image_profile() :: map()
  def default_image_profile do
    name = registry()["default_image_profile"]
    Enum.find(image_profiles(), &(&1["name"] == name)) || raise_unnamed("default_image_profile")
  end

  @doc """
  The low-fidelity profile spec-10 §5.4 permits as a loading state, computed from
  the image's own pixels. It asserts nothing the image does not.
  """
  @spec placeholder_profile() :: map()
  def placeholder_profile, do: fetch("placeholder_profile")

  @doc """
  The aspect ratio a surface reserves for a category before a probe has run
  (spec-10 §11.2), or nil for a companion kind that is never presented as a
  holding (spec-10 §12.2).

  A category the registry does not name raises: a surface that guessed a ratio
  would reflow the moment the real geometry arrived.
  """
  @spec assumed_aspect_ratio(String.t()) :: float() | nil
  def assumed_aspect_ratio(category), do: Map.fetch!(fetch("assumed_aspect_ratio"), category)

  @doc """
  Every category the registry names a ratio for, which is every category presented
  as a holding.
  """
  @spec categories_with_ratio() :: [String.t()]
  def categories_with_ratio do
    for {category, ratio} <- fetch("assumed_aspect_ratio"), ratio != nil, do: category
  end

  @doc """
  The pixel count above which a scan is tiled rather than served by profile, and
  the tile geometry (spec-10 §11.2).
  """
  @spec tiling() :: map()
  def tiling, do: fetch("tiling")

  @spec trickplay() :: map()
  def trickplay, do: fetch("trickplay")

  @doc """
  Where in a moving image the poster frame is taken.

  A proportion rather than a fixed offset, so it clears a logo and a cold open;
  bounded at both ends, so a short clip does not take frame zero and a long film
  does not take a frame far enough in to spoil it.
  """
  @spec key_frame() :: map()
  def key_frame, do: fetch("key_frame")

  @doc """
  The overview waveform: a fixed point count independent of duration, which is
  what a transport bar draws (spec-10 §11.4).
  """
  @spec waveform_overview() :: map()
  def waveform_overview, do: Map.fetch!(fetch("waveform_profiles"), "overview")

  @doc """
  The detail waveforms, whose size scales with duration, generated on demand for
  inspecting a region.
  """
  @spec waveform_detail() :: [map()]
  def waveform_detail, do: Map.fetch!(fetch("waveform_profiles"), "detail")

  @spec text_profiles() :: [map()]
  def text_profiles, do: fetch("text_profiles")

  @doc """
  The profiles generated at ingest because they are cheap and universally needed
  (spec-10 §11.6). Everything else is generated on demand.

  Nothing here is exempt from eviction. These return on the next scheduling pass,
  which is what makes the eviction bound safe.
  """
  @spec generated_at_ingest() :: [String.t()]
  def generated_at_ingest, do: fetch("generated_at_ingest")

  defp fetch(key), do: Map.fetch!(registry(), key)

  defp raise_unnamed(key),
    do: raise(KeyError, "#{key} names a profile the registry does not hold")

  defp registry, do: Registry.read(@source)
end
