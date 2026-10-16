defmodule MirrorWeb.SaveBarLiveTest do
  @moduledoc """
  The slot bar at the top of every page (EPIC-012). The browser half (the folder handle, reading
  and writing files) is not run here: these tests play the browser's part by sending the events the
  `SaveSlots` hook sends, and check what the server answers.
  """
  use MirrorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Mirror.{SaveManager, SessionStore, WizardFixture}

  setup %{conn: conn} do
    sid = "save-bar-test-#{System.unique_integer([:positive])}"

    {:ok, view, _} =
      live_isolated(conn, MirrorWeb.SaveBarLive, session: %{"mirror_session_id" => sid})

    %{view: view, sid: sid, conn: init_test_session(conn, %{"mirror_session_id" => sid})}
  end

  defp raw, do: WizardFixture.synthetic()
  defp b64(bytes), do: Base.encode64(bytes)

  defp folder(view, slots),
    do: render_hook(view, "folder", %{"name" => "MAGIC", "slots" => slots})

  defp load_slot(view, slot, bytes \\ raw()),
    do: render_hook(view, "slot_bytes", %{"slot" => slot, "data" => b64(bytes)})

  # Something Mirror changed in the save, as a wizard edit does.
  defp edit(sid) do
    {:ok, _} =
      SessionStore.update(sid, fn state ->
        %{
          state
          | save: %{state.save | raw: WizardFixture.field(state.save.raw, 0, 0x24, <<99, 0>>)}
        }
      end)
  end

  defp badge_shown?(view), do: not (view |> element("#unsaved-badge") |> render() =~ "invisible")

  test "before a folder is chosen it offers to choose one", %{view: view} do
    assert has_element?(view, "#choose-folder")
    refute has_element?(view, "#slot-1")
  end

  test "a browser without the folder picker says what it needs", %{view: view} do
    render_hook(view, "unsupported", %{})
    assert has_element?(view, "#save-bar-unsupported", "Chrome or Edge")
  end

  test "a lost permission asks to reconnect", %{view: view} do
    render_hook(view, "needs_permission", %{"name" => "MAGIC"})
    assert has_element?(view, "#reconnect-folder")
  end

  test "slots with a save are enabled, empty ones are not, and junk is ignored", %{view: view} do
    folder(view, [1, 3, 9, 12, "x"])

    for n <- [1, 3, 9], do: refute(has_element?(view, "#slot-#{n}[disabled]"))
    for n <- [2, 4, 5, 6, 7, 8], do: assert(has_element?(view, "#slot-#{n}[disabled]"))
  end

  describe "opening a slot" do
    test "asks the browser for the file, and loads the bytes it sends", %{view: view, sid: sid} do
      folder(view, [3])
      view |> element("#slot-3") |> render_click()
      assert_push_event(view, "read_slot", %{slot: 3})

      load_slot(view, 3)

      assert has_element?(view, "#save-bar-status", "Loaded SAVE3.GAM.")
      assert has_element?(view, "#save-bar-name", "SAVE3.GAM")
      assert SessionStore.get(sid).save.raw == raw()
      assert SessionStore.get(sid).save_path == "SAVE3.GAM"
      refute badge_shown?(view)
    end

    test "slot 9, the autosave, opens like the others", %{view: view, sid: sid} do
      folder(view, [9])
      view |> element("#slot-9") |> render_click()
      assert_push_event(view, "read_slot", %{slot: 9})
      load_slot(view, 9)
      assert SessionStore.get(sid).save_path == "SAVE9.GAM"
    end

    test "bytes that are not a save are refused and nothing changes", %{view: view, sid: sid} do
      folder(view, [1])
      load_slot(view, 1)
      before = SessionStore.get(sid)

      load_slot(view, 2, "not a save")
      assert has_element?(view, "#save-bar-status", "does not look like")
      assert SessionStore.get(sid).save.raw == before.save.raw

      render_hook(view, "slot_bytes", %{"slot" => 2, "data" => "%%%"})
      assert has_element?(view, "#save-bar-status", "did not come through")
    end

    test "a slot outside 1 to 9 does nothing", %{view: view, sid: sid} do
      render_hook(view, "slot_bytes", %{"slot" => 10, "data" => b64(raw())})
      assert SessionStore.get(sid) == nil
    end

    test "loading replaces the save the pages are showing", %{view: view, sid: sid, conn: conn} do
      load_slot(view, 1)
      {:ok, wizard, _} = live(conn, ~p"/wizard/1")
      assert has_element?(wizard, "#wizard-name", "Jafar")

      renamed = WizardFixture.field(raw(), 0, 0x01, String.pad_trailing("Merlin", 20, <<0>>))
      load_slot(view, 2, renamed)

      assert SessionStore.get(sid).save_path == "SAVE2.GAM"
      assert has_element?(wizard, "#wizard-name", "Merlin")
    end
  end

  describe "unsaved changes" do
    test "the badge is always in the page and only shows when there is something unsaved", %{
      view: view,
      sid: sid
    } do
      assert has_element?(view, "#unsaved-badge.invisible")
      load_slot(view, 1)
      assert has_element?(view, "#unsaved-badge.invisible")

      edit(sid)
      assert badge_shown?(view)
    end

    test "a wizard page edit shows it on the bar", %{view: view, sid: sid, conn: conn} do
      load_slot(view, 1)
      {:ok, wizard, _} = live(conn, ~p"/wizard/1")
      render_click(wizard, "toggle_edit", %{})

      wizard
      |> element("form[phx-submit=wizard_edit]")
      |> render_submit(%{"wizard" => %{"gold" => "5000"}})

      assert SaveManager.unsaved_count(SessionStore.get(sid)) > 0
      assert badge_shown?(view)
    end
  end

  describe "saving into a slot" do
    setup %{view: view} do
      folder(view, [1, 2])
      load_slot(view, 1)
      render_click(view, "set_mode", %{"mode" => "save"})
      :ok
    end

    test "an empty slot is written straight away, without a backup", %{view: view, sid: sid} do
      edit(sid)
      view |> element("#slot-5") |> render_click()

      assert_push_event(view, "write_slot", %{slot: 5, data: data, backup: false})
      {:ok, bytes} = Base.decode64(data)
      assert {:ok, ^bytes} = SaveManager.slot_bytes(SessionStore.get(sid))
      assert bytes != raw()

      # nothing is marked saved until the browser says the file is written
      assert badge_shown?(view)

      render_hook(view, "slot_written", %{"slot" => 5})
      refute badge_shown?(view)
      assert has_element?(view, "#save-bar-status", "Saved to SAVE5.GAM")
      assert has_element?(view, "#slot-5:not([disabled])")
      assert SessionStore.get(sid).save_path == "SAVE5.GAM"
      assert SessionStore.get(sid).save.raw == bytes
    end

    test "a full slot asks first, and Cancel writes nothing", %{view: view} do
      view |> element("#slot-2") |> render_click()
      assert has_element?(view, "#replace-confirm", "Replace SAVE2.GAM?")
      refute_push_event(view, "write_slot", _)

      view |> element("#cancel-replace") |> render_click()
      refute has_element?(view, "#replace-confirm")
      refute_push_event(view, "write_slot", _)
    end

    test "Replace writes the slot and asks the browser for a backup", %{view: view} do
      view |> element("#slot-2") |> render_click()
      view |> element("#confirm-replace") |> render_click()

      assert_push_event(view, "write_slot", %{slot: 2, backup: true})
      refute has_element?(view, "#replace-confirm")
    end

    test "slot 9, the autosave, is never written to", %{view: view} do
      assert has_element?(view, "#slot-9[disabled]")
      render_click(view, "pick_slot", %{"slot" => "9"})
      assert has_element?(view, "#save-bar-status", "autosave")
      refute_push_event(view, "write_slot", _)
    end

    test "a failed write leaves the edits marked unsaved", %{view: view, sid: sid} do
      edit(sid)
      view |> element("#slot-5") |> render_click()
      assert_push_event(view, "write_slot", %{slot: 5})

      render_hook(view, "slot_error", %{
        "message" => "Could not save SAVE5.GAM, nothing was changed: disk full"
      })

      assert has_element?(view, "#save-bar-status", "disk full")
      assert badge_shown?(view)

      # and a late "written" for it is ignored
      render_hook(view, "slot_written", %{"slot" => 5})
      assert badge_shown?(view)
    end

    test "an edit made while the file was being written stays unsaved", %{view: view, sid: sid} do
      edit(sid)
      view |> element("#slot-5") |> render_click()
      assert_push_event(view, "write_slot", %{slot: 5})

      {:ok, _} =
        SessionStore.update(sid, fn s ->
          %{s | save: %{s.save | raw: WizardFixture.field(s.save.raw, 0, 0x24, <<7, 0>>)}}
        end)

      render_hook(view, "slot_written", %{"slot" => 5})
      assert badge_shown?(view)
    end
  end

  test "saving with nothing loaded says so", %{view: view} do
    folder(view, [1])
    render_click(view, "set_mode", %{"mode" => "save"})
    view |> element("#slot-4") |> render_click()
    assert has_element?(view, "#save-bar-status", "Load a save first")
    refute_push_event(view, "write_slot", _)
  end

  test "the bar is on every kind of page, once", %{conn: conn} do
    for path <- [~p"/", ~p"/arcanus", ~p"/lab/arcanus", ~p"/tile-probe"] do
      html = conn |> get(path) |> html_response(200)
      assert length(Regex.scan(~r/id="save-bar"/, html)) == 1, path
    end
  end
end
