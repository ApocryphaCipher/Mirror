defmodule MirrorWeb.WizardLiveTest do
  use MirrorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Mirror.SessionStore

  setup %{conn: conn} do
    sid = "wizard-test-#{System.unique_integer([:positive])}"
    %{conn: init_test_session(conn, %{"mirror_session_id" => sid}), sid: sid}
  end

  defp load_save(sid) do
    state = Mirror.SaveManager.normalize_state(%{save: %{raw: Mirror.WizardFixture.synthetic()}})
    SessionStore.put(sid, state)
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
    raw = Mirror.WizardFixture.synthetic()
    <<head::binary-size(0x9E8 + 0x4C8 + 1), _::binary-size(20), tail::binary>> = raw
    SessionStore.put(sid, %{save: %{raw: head <> :binary.copy(<<0>>, 20) <> tail}})

    assert has_element?(view, "#wizard-missing", "There is no wizard 2")
  end

  describe "editing" do
    defp submit(view, fields),
      do: view |> element("#wizard-form") |> render_submit(%{"wizard" => fields})

    test "the form appears in edit mode, an apply is one undo step and shows on the page",
         %{conn: conn, sid: sid} do
      load_save(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      refute has_element?(view, "#wizard-form")

      view |> element("#wizard-edit-toggle") |> render_click()
      assert has_element?(view, "#wizard-form")

      before = SessionStore.get(sid)
      submit(view, %{"gold" => "5000", "name" => "Jafar the Great", "retorts_present" => "1"})

      assert has_element?(view, "#wizard-note", "Edited Jafar: gold 5000")
      assert has_element?(view, "#wizard-name", "Jafar the Great")
      assert render(view) =~ "5000"

      after_state = SessionStore.get(sid)
      assert Mirror.Editor.changed_record_count(after_state) == 1
      assert length(after_state.history.arcanus) == length(before.history.arcanus) + 1

      # Undo restores the old bytes
      {undone, _} = Mirror.Editor.undo(after_state, :arcanus)
      assert undone.save.raw == before.save.raw
    end

    test "a bad value is refused with the reason and changes nothing", %{conn: conn, sid: sid} do
      load_save(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      view |> element("#wizard-edit-toggle") |> render_click()
      raw = SessionStore.get(sid).save.raw

      submit(view, %{"gold" => "99999"})
      assert has_element?(view, "#wizard-note", "0 to 30000")

      submit(view, %{"name" => "Zoë"})
      assert has_element?(view, "#wizard-note", "no accents")

      submit(view, %{"gold" => "1234"})
      assert has_element?(view, "#wizard-note", "Nothing to change")

      assert SessionStore.get(sid).save.raw == raw
    end

    test "an apply compares with the save as it is now, not as the page was drawn",
         %{conn: conn, sid: sid} do
      load_save(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      view |> element("#wizard-edit-toggle") |> render_click()

      # another tab changes the gold and the name after this page was drawn
      {:ok, _} =
        SessionStore.update(sid, fn current ->
          {:ok, raw, _} =
            Mirror.SaveFile.Structures.edit_wizard(current.save.raw, 0, gold: 111, name: "Merlin")

          put_in(current.save.raw, raw)
        end)

      # this form was drawn with gold 1234 and the old name, and only mana is changed on it
      submit(view, %{"gold" => "111", "name" => "Merlin", "mana" => "9"})

      assert has_element?(view, "#wizard-note", "Edited Merlin: mana 9")
      refute has_element?(view, "#wizard-note", "gold")
    end

    test "malformed form values show a note instead of crashing the page", %{conn: conn, sid: sid} do
      load_save(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      view |> element("#wizard-edit-toggle") |> render_click()

      render_hook(view, "wizard_edit", %{"wizard" => %{"name" => nil}})
      assert has_element?(view, "#wizard-note", "1 to 19")
      render_hook(view, "wizard_edit", %{"wizard" => %{"books" => "x"}})
      assert has_element?(view, "#wizard-note", "Books")

      render_hook(view, "wizard_edit", %{
        "wizard" => %{"retorts_present" => "1", "retorts" => nil}
      })

      assert has_element?(view, "#wizard-note", "retorts")
    end
  end
end
