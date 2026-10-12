defmodule MirrorWeb.WizardLiveTest do
  use MirrorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Mirror.SessionStore

  setup %{conn: conn} do
    sid = "wizard-test-#{System.unique_integer([:positive])}"
    %{conn: init_test_session(conn, %{"mirror_session_id" => sid}), sid: sid}
  end

  defp load_save(sid) do
    SessionStore.put(sid, %{save: %{raw: MirrorWeb.WizardPanelTest.synthetic()}})
  end

  test "no save loaded says so", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/wizard/1")
    assert html =~ "No save is loaded"
  end

  test "shows the wizard on a gradient of the banner colour", %{conn: conn, sid: sid} do
    load_save(sid)
    {:ok, view, html} = live(conn, ~p"/wizard/1")

    assert has_element?(view, "#wizard-name", "Jafar")
    assert html =~ "1234"
    assert html =~ "12 Sorcery"
    assert html =~ "Alchemy, Famous"
    assert html =~ "linear-gradient(to bottom, #{MirrorWeb.WizardPanel.colour(:blue)}"
    assert has_element?(view, "#wizard-circle[href='/myrror']")
    assert has_element?(view, "#wizard-switcher a[href='/wizard/2']", "Sharee")
  end

  test "a missing wizard answers 404 with the note; an existing one 200", %{conn: conn, sid: sid} do
    assert get(conn, ~p"/wizard/6").status == 404
    assert get(conn, ~p"/wizard/abc").status == 404
    # in range, nothing loaded yet: 200 with "no save is loaded"
    assert html_response(get(conn, ~p"/wizard/1"), 200) =~ "No save is loaded"

    load_save(sid)
    assert get(conn, ~p"/wizard/1").status == 200
    resp = get(conn, ~p"/wizard/3")
    assert html_response(resp, 404) =~ "There is no wizard 3"
  end

  test "the page says so when the wizard disappears from the save", %{conn: conn, sid: sid} do
    load_save(sid)
    {:ok, view, _} = live(conn, ~p"/wizard/2")
    refute has_element?(view, "#wizard-missing")

    # the loaded save changes underneath the open page (another tab, an undo, a new load)
    raw = MirrorWeb.WizardPanelTest.synthetic()
    <<head::binary-size(0x9E8 + 0x4C8 + 1), _::binary-size(20), tail::binary>> = raw
    SessionStore.put(sid, %{save: %{raw: head <> :binary.copy(<<0>>, 20) <> tail}})

    assert has_element?(view, "#wizard-missing", "There is no wizard 2")
  end
end
