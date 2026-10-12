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

  test "a missing wizard says so", %{conn: conn, sid: sid} do
    load_save(sid)

    for id <- ["3", "6", "0", "abc"] do
      {:ok, view, _} = live(conn, ~p"/wizard/#{id}")
      assert has_element?(view, "#wizard-missing")
    end
  end
end
