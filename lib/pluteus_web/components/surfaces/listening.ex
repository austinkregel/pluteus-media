defmodule PluteusWeb.Surfaces.Listening do
  @moduledoc """
  The transport and its chapter list: the surface a reading and a podcast episode are
  presented on ([spec-10] §12.1).

  A reading is one long thing rather than a list of tracks, so what the surface offers is
  where to go in it: the chapters its container states, each pressable to be taken there.
  What plays it is the chrome's own transport, which is why the reading outlives moving
  to another surface.

  A reading carried by several files is still one reading. The parts are where the bytes
  are and not divisions anybody made, so they are not listed as though they were
  chapters: §12.3's position runs over the whole, and the transport spans the parts.
  """

  use PluteusWeb, :html

  alias Pluteus.Playback
  alias PluteusWeb.Surfaces.Medium

  attr :name, :string, required: true
  attr :category, :string, required: true
  attr :playable, :any, required: true
  attr :chapters, :list, required: true
  attr :credited, :list, required: true
  attr :cover, :any, required: true
  attr :reserved, :any, required: true
  attr :playing, :boolean, required: true

  def surface(assigns) do
    ~H"""
    <div class="flex w-full flex-1 flex-col">
      <Medium.band name={@name} category={@category} />

      <div class="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-8 p-4 sm:p-6">
        <div class="flex flex-col gap-6 sm:flex-row">
          <.cover cover={@cover} name={@name} reserved={@reserved} />

          <div class="flex min-w-0 grow flex-col gap-3">
            <p
              :for={credit <- @credited}
              class="text-body-md text-on-surface-strong"
            >
              {in_role(credit.role)} {Enum.join(credit.names, ", ")}
            </p>

            <p class="text-body-sm text-on-surface-muted">{said(@playable, @chapters)}</p>

            <.start playable={@playable} playing={@playing} />
          </div>
        </div>

        <.chapters chapters={@chapters} />
      </div>
    </div>
    """
  end

  attr :cover, :any, required: true
  attr :name, :string, required: true
  attr :reserved, :any, required: true

  defp cover(%{cover: nil} = assigns), do: ~H""

  defp cover(assigns) do
    ~H"""
    <img
      id="listening-cover"
      src={~p"/manifestations/#{@cover}/presentation/image-640"}
      alt={"The cover of #{@name}"}
      style={@reserved && "aspect-ratio: #{@reserved}"}
      class={[
        "w-full shrink-0 rounded-md object-contain sm:w-64",
        "border-[length:var(--sys-border-width-hairline)] border-border-subtle",
        "bg-surface-raised"
      ]}
    />
    """
  end

  attr :playable, :any, required: true
  attr :playing, :boolean, required: true

  defp start(%{playable: {:error, refusal}} = assigns) do
    assigns = assign(assigns, :why, Playback.why(refusal))

    ~H"""
    <p id="listening-refusal" class="text-body-sm text-on-surface-muted">{@why}</p>
    """
  end

  defp start(assigns) do
    ~H"""
    <button
      type="button"
      id="listening-start"
      phx-click="play-entry"
      phx-value-index="0"
      aria-current={@playing && "true"}
      class={[
        "min-h-target-pointer w-fit shrink-0 rounded-md px-4",
        "border-[length:var(--sys-border-width-component)] border-border-strong",
        "text-body-md text-on-surface-strong hover:bg-fill-subtle-strong"
      ]}
    >
      {if @playing, do: "Playing", else: "Play"}
    </button>
    """
  end

  attr :chapters, :list, required: true

  defp chapters(%{chapters: []} = assigns) do
    ~H"""
    <p id="listening-chapters-absent" class="text-body-md text-on-surface-muted">
      Nothing in this states where its chapters are.
    </p>
    """
  end

  defp chapters(assigns) do
    ~H"""
    <ol id="listening-chapters" class="flex flex-col">
      <li :for={{chapter, index} <- Enum.with_index(@chapters)}>
        <button
          type="button"
          phx-click="chapter"
          phx-value-index={index}
          class={[
            "flex min-h-target-touch w-full items-center gap-3 px-2 text-left",
            "border-b-[length:var(--sys-border-width-hairline)] border-border-subtle",
            "hover:bg-fill-subtle-strong"
          ]}
        >
          <span class="w-6 shrink-0 font-mono text-caption text-on-surface-muted">
            {index + 1}
          </span>
          <span class="grow truncate text-body-sm text-on-surface-strong">{chapter.name}</span>
          <span class="shrink-0 font-mono text-caption text-on-surface-muted">
            {Medium.clock(chapter.start_ms)}
          </span>
        </button>
      </li>
    </ol>
    """
  end

  @doc """
  How a credit's role is said to a person (§8.5).

  A clause each over `Pluteus.Catalog.Credit.roles/0` and no catch-all, so a role the
  catalog gains reaches a person in words rather than in the model's own vocabulary.
  """
  @spec in_role(atom()) :: String.t()
  def in_role(:author), do: "Written by"
  def in_role(:narrator), do: "Read by"
  def in_role(:artist), do: "By"
  def in_role(:album_artist), do: "By"

  # How long the reading is and how many chapters it holds, where each is recorded. A
  # length nobody measured is left unsaid rather than drawn as a dash beside a count.
  defp said(playable, chapters) do
    [extent(playable), counted(chapters)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp extent({:error, _refusal}), do: nil
  defp extent({:ok, %{to_ms: to, from_ms: from}}) when is_integer(to), do: Medium.clock(to - from)

  defp extent({:ok, %{parts: parts}}) do
    durations = Enum.map(parts, & &1.duration_ms)

    if Enum.any?(durations, &is_nil/1), do: nil, else: Medium.clock(Enum.sum(durations))
  end

  defp counted([]), do: nil
  defp counted([_one]), do: "1 chapter"
  defp counted(chapters), do: "#{length(chapters)} chapters"
end
