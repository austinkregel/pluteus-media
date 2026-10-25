defmodule PluteusWeb.Picture do
  @moduledoc """
  An image a surface asks for, laid over the glyph that stands for it.

  The glyph is always drawn and the image covers it once it arrives, so a box with no
  image shows the same thing whatever the reason: no source to ask for, a derivative
  still being made (§11.1 answers 202), one that cannot be made (204), or a request that
  failed. Each of those would otherwise leave an empty box, and an empty box reads as a
  page that failed to load rather than as a holding with no picture.

  The image is removed when it fails rather than left as the browser's broken-image mark,
  which is what uncovers the glyph beneath it.
  """

  use Phoenix.Component

  attr :src, :string, default: nil, doc: "the image, or nil where there is none to ask for"
  attr :loading, :string, default: "lazy", values: ~w(lazy eager)
  slot :inner_block, required: true, doc: "the glyph that stands for the image"

  def picture(assigns) do
    ~H"""
    <span class="relative flex size-full items-center justify-center">
      {render_slot(@inner_block)}
      <img
        :if={@src}
        src={@src}
        alt=""
        loading={@loading}
        class="absolute inset-0 size-full object-cover"
        onerror="this.remove()"
      />
    </span>
    """
  end

  @doc """
  The class colour a glyph for a broad class is drawn in.

  Each is a complete literal: a class assembled from a value generates no rule, and the
  glyph renders colourless with nothing reporting it.
  """
  @spec hue(String.t()) :: String.t()
  def hue("video"), do: "text-class-video"
  def hue("audio"), do: "text-class-audio"
  def hue("image"), do: "text-class-image"
  def hue("text"), do: "text-class-text"
  def hue("software"), do: "text-class-software"
  def hue("package"), do: "text-class-package"
end
