defmodule Pluteus.Design.Tokens do
  @moduledoc """
  The design token file, and the lookups the build and the assertions read it
  through (Annex A.1).

  Annex A holds that every value in it "is a starting value, maintained as
  spec-10 §20's registry", so this is the `design_language_tokens` registry that
  §20 names: data under `priv/`, replaced by a release, read once and held for the
  life of the node exactly as `Pluteus.Registry` does for the other five.

  A path is dotted as A.1.5 writes it — `sys.color.surface.raised` — and a path the
  file does not hold raises. §20 forbids a code path supplying a value a registry
  omits, so there is no lookup here that answers `nil`.

  **Aliases are followed, not flattened away.** A.1.4's tiers are the point: `sys`
  holds roles that reference `base`, and `resolve!/1` walks the chain so a caller
  can ask for a role's value without knowing which primitive answers it, while
  `fetch!/1` returns the token as authored so a lint can see the reference.
  """

  @default "tokens"

  @doc """
  The whole token document for a context, decoded.

  `"tokens"` is the default resolution — dark, near, comfortable, normal, full
  motion. Any other name is an override file under `contexts/`.
  """
  @spec read(String.t()) :: map()
  def read(context \\ @default) do
    key = {__MODULE__, context}

    case :persistent_term.get(key, nil) do
      nil ->
        loaded = context |> path() |> File.read!() |> Jason.decode!()
        :persistent_term.put(key, loaded)
        loaded

      loaded ->
        loaded
    end
  end

  @doc """
  One token, as authored, including its `$value` and any reference in it.
  """
  @spec fetch!(String.t(), String.t()) :: map()
  def fetch!(dotted, context \\ @default) do
    segments = String.split(dotted, ".")

    case get_in(read(context), segments) do
      %{"$value" => _value} = token ->
        token

      nil ->
        raise KeyError, "#{dotted} is not a token the design language holds"

      %{} = group ->
        raise KeyError,
              "#{dotted} is a group of #{map_size(group)} and not a token"
    end
  end

  @doc """
  One token's value with every alias followed to a concrete value.

  A reference is DTCG's curly-brace form, `{base.grey.01}`. A chain that does not
  end in a value raises rather than returning the reference, because a caller
  asking for a value and receiving a path would write the path into a stylesheet.
  """
  @spec resolve!(String.t(), String.t()) :: term()
  def resolve!(dotted, context \\ @default) do
    case fetch!(dotted, context)["$value"] do
      "{" <> _rest = reference -> reference |> dereference() |> resolve!(context)
      value -> value
    end
  end

  @doc """
  Every token in a context, as a map of dotted path to the token as authored.

  What the lints read: A.1.4's tier rule and A.1.5's naming rules are both
  statements about the whole set rather than about any one token.
  """
  @spec all(String.t()) :: %{String.t() => map()}
  def all(context \\ @default) do
    read(context) |> walk([], %{})
  end

  @doc """
  Every token whose `$type` resolves to `type`, by dotted path.

  A group's `$type` is inherited by its children unless a child overrides it, so
  the type of a token is not always written on the token.
  """
  @spec of_type(String.t(), String.t()) :: %{String.t() => map()}
  def of_type(type, context \\ @default) do
    context |> all() |> Map.filter(fn {path, token} -> typed(path, token, context) == type end)
  end

  @doc """
  The `$type` in force for a token, whether written on it or inherited.
  """
  @spec typed(String.t(), map(), String.t()) :: String.t() | nil
  def typed(dotted, token, context \\ @default) do
    case token["$type"] do
      nil -> inherited(String.split(dotted, "."), read(context))
      written -> written
    end
  end

  @doc """
  The contexts with an override file, by the modifier each belongs to.
  """
  @spec contexts() :: %{String.t() => [String.t()]}
  def contexts do
    resolver()
    |> Map.fetch!("modifiers")
    |> Map.new(fn {modifier, %{"contexts" => contexts}} ->
      {modifier, Map.keys(contexts)}
    end)
  end

  @doc """
  Every context that overrides something, as `{modifier, context}`.

  A modifier's default context overrides nothing and has no file, because the
  default is what the token file already holds — so this is what a build iterates
  rather than every context a modifier declares.
  """
  @spec overrides() :: [{String.t(), String.t()}]
  def overrides do
    for {modifier, %{"contexts" => contexts}} <- Map.fetch!(resolver(), "modifiers"),
        {context, sources} <- contexts,
        sources != [] do
      {modifier, context}
    end
    |> Enum.sort()
  end

  @doc """
  The resolver manifest: which modifiers are declared, and what each resolves.
  """
  @spec resolver() :: map()
  def resolver do
    key = {__MODULE__, :resolver}

    case :persistent_term.get(key, nil) do
      nil ->
        loaded = root() |> Path.join("resolver.json") |> File.read!() |> Jason.decode!()
        :persistent_term.put(key, loaded)
        loaded

      loaded ->
        loaded
    end
  end

  @doc """
  Where the token files live.
  """
  @spec root() :: Path.t()
  def root, do: :pluteus |> :code.priv_dir() |> Path.join("design")

  @doc """
  Forgets every cached document, so the next read comes from disk.

  The cache is what makes a lookup free for the life of the node, and it is also what
  would make a rebuild after an edit regenerate the values it already had — the same
  stylesheet, with nothing to say the edit had been ignored. So a caller that has just
  changed a file on disk clears the cache first. Nothing in a running deployment does:
  `priv` is replaced by a release, not edited underneath one.
  """
  @spec forget() :: :ok
  def forget do
    for {{__MODULE__, _which} = key, _document} <- :persistent_term.get() do
      :persistent_term.erase(key)
    end

    :ok
  end

  defp path(@default), do: root() |> Path.join("tokens.json")
  defp path(context), do: root() |> Path.join("contexts/#{context}.json")

  defp dereference("{" <> rest), do: String.trim_trailing(rest, "}")

  # A token is a map carrying `$value`; anything else that is a map is a group.
  # Keys beginning `$` are the format's own and are never path segments.
  defp walk(%{"$value" => _value} = token, path, found) do
    Map.put(found, Enum.join(Enum.reverse(path), "."), token)
  end

  defp walk(%{} = group, path, found) do
    Enum.reduce(group, found, fn
      {"$" <> _own, _value}, found -> found
      {segment, child}, found -> walk(child, [segment | path], found)
    end)
  end

  defp walk(_scalar, _path, found), do: found

  defp inherited([], _node), do: nil

  defp inherited([segment | rest], node) do
    child = Map.get(node, segment, %{})

    case inherited(rest, child) do
      nil -> node["$type"]
      found -> found
    end
  end
end
