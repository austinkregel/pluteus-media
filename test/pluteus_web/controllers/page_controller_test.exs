defmodule PluteusWeb.PageControllerTest do
  use PluteusWeb.ConnCase

  alias Pluteus.Design.Tokens

  test "GET / renders the design language", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "The design language"
  end

  test "GET / shows every sys colour role", %{conn: conn} do
    # The page reads the roles from the token file, so a role added to the language
    # appears here without the template being edited — and this is what says so. A.11
    # makes the `sys` names the public interface, and a role nothing renders is a role
    # nobody sees break.
    html = conn |> get(~p"/") |> html_response(200)

    roles =
      Tokens.all()
      |> Map.keys()
      |> Enum.filter(&String.starts_with?(&1, "sys.color."))

    for role <- roles do
      variable = role |> String.replace_prefix("sys.", "sys-") |> String.replace(".", "-")

      assert html =~ "var(--#{variable})", "#{role} is not rendered anywhere"
    end
  end

  test "GET / offers every context, and the two attributes each records", %{conn: conn} do
    # A.10.1 requires the resolved value and the person's intent both be recorded, so
    # that "follow the system" is a third state rather than a lost one. The script is
    # what writes them; this asserts the controls that drive it exist for all five
    # modifiers, since a modifier with no control is one nobody can reach.
    html = conn |> get(~p"/") |> html_response(200)

    for {modifier, contexts} <- PluteusWeb.Layouts.modifiers() do
      assert html =~ ~s(data-modifier="#{modifier}")

      for context <- contexts do
        assert html =~ ~s(data-context="#{context}")
      end
    end

    assert html =~ ~s|root.setAttribute(`data-${modifier}`, resolve(modifier, intent));|
    assert html =~ ~s|root.setAttribute(`data-${modifier}-intent`, intent);|
  end

  test "GET /notices carries the notice every vendored thing states", %{conn: conn} do
    # A.8.1 puts half of the glyph set's licence obligation beside the files and the
    # other half in the interface, so this page is what the licence requires. The notices
    # are read from the files that state them, and this asserts each one arrived.
    html = conn |> get(~p"/notices") |> html_response(200)

    assert html =~ "Copyright (c) Tailwind Labs, Inc."
    assert html =~ "The above copyright notice and this permission notice shall be included"

    for notice <- PluteusWeb.Notices.all() do
      assert html =~ notice.name
      assert html =~ notice.vendored
    end
  end

  test "GET / links to the notices, since a page nothing reaches discharges nothing",
       %{conn: conn} do
    assert conn |> get(~p"/") |> html_response(200) =~ ~s(href="/notices")
  end

  test "GET / carries no daisyUI class and no framework marketing", %{conn: conn} do
    # A.10.1 removes daisyUI because its flat named-theme axis cannot express A.1.6's
    # five orthogonal modifiers, and because its component classes bind a component to
    # daisyUI's token names rather than to `sys`, which A.1.4 forbids. A class left
    # behind would render as nothing at all rather than as an error.
    html = conn |> get(~p"/") |> html_response(200)

    for class <- ~w(btn-primary alert-info card badge base-content base-200 toast) do
      refute html =~ ~s(class="#{class}), "a daisyUI class survives: #{class}"
      refute html =~ " #{class} ", "a daisyUI class survives: #{class}"
    end

    refute html =~ "Peace of mind from prototype to production"
    refute html =~ "phoenixframework.org"
  end
end
