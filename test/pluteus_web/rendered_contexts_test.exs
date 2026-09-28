defmodule PluteusWeb.RenderedContextsTest do
  @moduledoc """
  What the document root says about a principal's contexts, and what it deliberately
  does not.

  spec-10 §14.5 makes a motion, contrast, text-size, caption and described-audio
  preference that principal's and "MUST NOT be visible to another"; §21 adds that they
  "are not household-visible". Two of them were kept in `localStorage`, which on a
  household browser is one store shared by everyone who uses it — so what is asserted
  here is that a principal's own intents come from the server, and that nothing of one
  principal's reaches another's render.

  Annex A.10.1 requires the resolved value and the intent both be recorded, "so that
  'follow the system' is a third state rather than a lost one", and the generated
  stylesheet's fallbacks are scoped `:root:not([data-<modifier>])`. Which attributes
  appear is therefore load-bearing in both directions: one missing switches a media
  query on when the person had chosen, and one present switches it off when they had
  not.
  """

  use PluteusWeb.ConnCase, async: true

  alias Pluteus.Preferences
  alias Pluteus.Preferences.Registry
  alias Pluteus.Principals
  alias PluteusWeb.Contexts
  alias PluteusWeb.Layouts

  defp member(context) do
    {:ok, principal} = Principals.create_principal(%{role: "member"})
    viewer = a_subject()
    {:ok, _bound} = Principals.bind_identity(principal.id, issuer(), viewer)

    Map.merge(context, %{principal: principal, viewer: viewer})
  end

  defp rendered(conn, viewer), do: conn |> through_proxy(viewer) |> get("/") |> html_response(200)

  describe "Annex A.1.6. Which modifiers the store answers for" do
    test "the stored set is the registry's and the controls', never a list of its own" do
      # A modifier is stored where the preference registry names a key after it. Were the
      # two written out separately, a control could offer a context the store refuses and
      # the only report of it would be a 422 nobody sees.
      #
      # The order is the resolver's `resolutionOrder`, since the modifiers are read from
      # the declaration rather than listed again.
      assert Contexts.stored() == ~w(theme contrast motion density)
    end

    test "distance is not stored, because §4.4 records it with the device" do
      # §4.4:198 records the declaration "with the device" and A.10.3:1088 makes
      # `distance` follow from it rather than from anything a person carries between
      # screens. A key for it would be a second answer to a settled question.
      refute "distance" in Contexts.stored()
      refute "distance" in Registry.keys()
    end

    test "every context a control offers is one the store admits" do
      # A control offering a context outside the key's domain would be a button whose
      # only effect is a refusal.
      for {modifier, contexts} <- Layouts.modifiers(), modifier in Contexts.stored() do
        %{"kind" => "one_of", "values" => admitted} = Registry.domain(modifier)

        assert Enum.sort(contexts) == Enum.sort(admitted),
               "#{modifier}'s controls and its domain disagree"
      end
    end
  end

  describe "Annex A.10.1. The resolved value and the intent" do
    setup ~w(member)a

    test "an outright choice renders both attributes", %{
      conn: conn,
      principal: principal,
      viewer: viewer
    } do
      {:ok, _set} = Preferences.set(principal.id, "theme", "light")

      html = rendered(conn, viewer)

      assert html =~ ~s(data-theme="light")
      assert html =~ ~s(data-theme-intent="light")
    end

    test "a system intent renders the intent and no resolved value", %{
      conn: conn,
      principal: principal,
      viewer: viewer
    } do
      # `system` means a media feature decides, and a media feature is a fact about the
      # browser. The stylesheet's query is scoped `:root:not([data-theme])`, so the
      # resolved attribute's absence is the condition it waits on: rendering one here
      # would switch the query off with nothing put in its place.
      {:ok, _set} = Preferences.set(principal.id, "theme", "system")

      html = rendered(conn, viewer)

      assert html =~ ~s(data-theme-intent="system")
      refute html =~ ~s(data-theme=")
    end

    test "choosing the default context still renders it, or the machine overrules the person",
         %{conn: conn, principal: principal, viewer: viewer} do
      # `dark` is what `:root` already holds, so `data-theme="dark"` matches no rule in
      # the stylesheet. Matching nothing is not the same as doing nothing: it is what
      # takes `@media (prefers-color-scheme: light)` out of force. Dropping the attribute
      # for being the default would let a machine set to light overrule someone who asked
      # for dark.
      {:ok, _set} = Preferences.set(principal.id, "theme", "dark")

      html = rendered(conn, viewer)

      assert html =~ ~s(data-theme="dark")
      assert html =~ ~s(data-theme-intent="dark")
    end

    test "the stored modifiers are named to the script", %{conn: conn, viewer: viewer} do
      named = Contexts.stored() |> Enum.sort() |> Enum.join(" ")

      assert rendered(conn, viewer) =~ ~s(data-stored="#{named}")
    end

    test "a control states the principal's own choice in the first paint", %{
      conn: conn,
      principal: principal,
      viewer: viewer
    } do
      {:ok, _set} = Preferences.set(principal.id, "density", "compact")

      html = rendered(conn, viewer)

      assert html =~ ~r/data-modifier="density"\s+data-context="compact"\s+aria-pressed="true"/

      assert html =~
               ~r/data-modifier="density"\s+data-context="comfortable"\s+aria-pressed="false"/
    end
  end

  describe "spec-10 §14.5. Not visible to another" do
    setup ~w(member)a

    test "one principal's intent does not reach another's render", %{
      conn: conn,
      principal: principal
    } do
      {:ok, _set} = Preferences.set(principal.id, "motion", "reduced")

      other = a_subject()
      html = rendered(conn, other)

      refute html =~ ~s(data-motion="reduced")
      assert html =~ ~s(data-motion-intent="#{Registry.default("motion")}")
    end

    test "what the wire stored is what the page renders", %{conn: conn, viewer: viewer} do
      # The same principal over both surfaces, so a preference set by a client is the one
      # the interface draws rather than a second copy of it.
      build_conn()
      |> through_proxy(viewer)
      |> put("/preferences", %{"preferences" => %{"contrast" => "more"}})
      |> json_response(200)

      assert rendered(conn, viewer) =~ ~s(data-contrast="more")
    end
  end

  describe "The script prefers what the server said" do
    test "a rendered intent outranks this browser's own key", %{conn: conn} do
      # The precedence is the whole of the fix: with `localStorage` first, the next person
      # to use a household browser inherits the last one's settings, which is what §14.5
      # forbids.
      html = conn |> get("/") |> html_response(200)

      {intent_at, _length} = :binary.match(html, "intents[modifier] ||")
      {storage_at, _length} = :binary.match(html, "localStorage.getItem(key(modifier))")

      assert intent_at < storage_at, "this browser's key is consulted before the server's"
    end

    test "a stored modifier does not read this browser's key at all", %{conn: conn} do
      # Ordering alone would leave the shared key as the fallback, so a stored modifier the
      # server said nothing about would inherit whatever the last person chose here.
      html = conn |> get("/") |> html_response(200)

      assert html =~ "(stored.has(modifier) ? null : localStorage.getItem(key(modifier)))"
    end

    test "this browser's key is touched only for a modifier the store does not hold", %{
      conn: conn
    } do
      # The device's key carries what someone chose here before the proxy named anybody, and
      # on a shared browser it is equally the last person's. A stored modifier neither reads
      # it nor writes it: writing would put a preference §14.5 makes confidential into
      # storage the next person can read, and clearing would lose an anonymous choice for
      # good the moment someone signs in.
      html = conn |> get("/") |> html_response(200)

      {branch_at, _length} = :binary.match(html, "if (stored.has(modifier)) {")
      {persist_at, _length} = :binary.match(html, "persist(modifier, context, previous);")
      {write_at, _length} = :binary.match(html, "localStorage.setItem(key(modifier), context)")
      {clear_at, _length} = :binary.match(html, "localStorage.removeItem(key(modifier))")

      assert branch_at < persist_at
      assert persist_at < write_at, "a stored modifier's press writes this browser's storage"
      assert persist_at < clear_at, "a stored modifier's press clears this browser's storage"
    end
  end
end
