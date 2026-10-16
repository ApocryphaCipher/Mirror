defmodule MirrorWeb.SaveSlotsTest do
  @moduledoc """
  Opening and saving from the browser (EPIC-012): the start page and the header's save slots.
  The browser half (the folder handle, reading and writing files) is not run here: these tests
  play the browser's part by sending the events the `SaveSlots` hook sends, and check what the
  server answers.
  """
  use MirrorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Mirror.{SaveManager, SessionStore, WizardFixture}

  setup %{conn: conn} do
    sid = "save-slots-test-#{System.unique_integer([:positive])}"
    %{sid: sid, conn: init_test_session(conn, %{"mirror_session_id" => sid})}
  end

  defp raw, do: WizardFixture.synthetic()

  defp folder(view, slots),
    do: render_hook(view, "slots:folder", %{"name" => "MAGIC", "slots" => slots})

  defp bytes(view, slot, data \\ raw()),
    do: render_hook(view, "slots:bytes", %{"slot" => slot, "data" => Base.encode64(data)})

  # A save already open in the session, as the start page leaves it.
  defp open_save(sid, name \\ "SAVE1.GAM") do
    {:ok, state, _} = SaveManager.load_bytes(raw(), name)
    SessionStore.put(sid, state)
  end

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

  describe "the start page" do
    test "asks for the game folder first and shows no slots", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")
      assert html =~ "Welcome to Mirror!"
      assert has_element?(view, "#choose-folder", "Choose folder")
      refute has_element?(view, "#slot-picker")
    end

    test "a browser without the folder picker says what it needs", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      render_hook(view, "slots:unsupported", %{})
      assert has_element?(view, "#slots-unsupported", "Chrome")
    end

    test "a lost permission asks to reconnect", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      render_hook(view, "slots:needs_permission", %{"name" => "MAGIC"})
      assert has_element?(view, "#reconnect-folder")
    end

    test "once the folder is chosen, slots with a save are enabled and empty ones are not", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/")
      folder(view, [1, 3, 9, 12, "x"])

      assert has_element?(view, "#folder-name", "MAGIC")
      for n <- [1, 3, 9], do: refute(has_element?(view, "#open-slot-#{n}[disabled]"))
      for n <- [2, 4, 5, 6, 7, 8], do: assert(has_element?(view, "#open-slot-#{n}[disabled]"))
      refute has_element?(view, "#no-saves")
    end

    test "a folder without saves says so", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      folder(view, [])
      assert has_element?(view, "#no-saves")
    end

    test "clicking a slot asks the browser for the file; the bytes open it and go on to the map",
         %{
           conn: conn,
           sid: sid
         } do
      {:ok, view, _} = live(conn, ~p"/")
      folder(view, [3])
      view |> element("#open-slot-3") |> render_click()
      assert_push_event(view, "slots:read", %{slot: 3})

      bytes(view, 3)

      assert_redirect(view, ~p"/arcanus")
      assert SessionStore.get(sid).save.raw == raw()
      assert SessionStore.get(sid).save_path == "SAVE3.GAM"
    end

    test "slot 9, the autosave, opens like the others", %{conn: conn, sid: sid} do
      {:ok, view, _} = live(conn, ~p"/")
      folder(view, [9])
      view |> element("#open-slot-9") |> render_click()
      assert_push_event(view, "slots:read", %{slot: 9})
      bytes(view, 9)
      assert SessionStore.get(sid).save_path == "SAVE9.GAM"
    end

    test "bytes that are not a save are refused, nothing changes, and the page stays", %{
      conn: conn,
      sid: sid
    } do
      open_save(sid)
      before = SessionStore.get(sid)
      {:ok, view, _} = live(conn, ~p"/")

      bytes(view, 2, "not a save")
      assert has_element?(view, "#slots-status", "does not look like")
      assert SessionStore.get(sid).save.raw == before.save.raw

      render_hook(view, "slots:bytes", %{"slot" => 2, "data" => "%%%"})
      assert has_element?(view, "#slots-status", "did not come through")
    end

    test "an empty slot, or one outside 1 to 9, opens nothing", %{conn: conn, sid: sid} do
      {:ok, view, _} = live(conn, ~p"/")
      folder(view, [1])
      render_hook(view, "slots:open", %{"slot" => "4"})
      assert has_element?(view, "#slots-status", "SAVE4.GAM is empty")

      render_hook(view, "slots:bytes", %{"slot" => 10, "data" => Base.encode64(raw())})
      assert SessionStore.get(sid) == nil
    end

    test "with a save already open, it offers to continue with it", %{conn: conn, sid: sid} do
      {:ok, view, _} = live(conn, ~p"/")
      refute has_element?(view, "#continue-link")

      open_save(sid, "SAVE6.GAM")
      assert has_element?(view, "#continue-link", "SAVE6.GAM")
    end
  end

  describe "the header" do
    test "is on every page, with the planes", %{conn: conn} do
      for path <- [~p"/arcanus", ~p"/myrror", ~p"/lab/arcanus", ~p"/tile-probe", ~p"/wizard/1"] do
        {:ok, view, _} = live(conn, path)
        assert has_element?(view, "#app-header a[href='/arcanus']", "Arcanus"), path
        assert has_element?(view, "#app-header a[href='/myrror']", "Myrror"), path
        assert has_element?(view, "#logo[href='/']"), path
      end
    end

    test "lists the save's wizards as links once a save is open", %{conn: conn, sid: sid} do
      {:ok, view, _} = live(conn, ~p"/arcanus")
      refute has_element?(view, "#header-wizards")

      open_save(sid)
      assert has_element?(view, "#header-wizards a[href='/wizard/1']", "Jafar")
    end

    test "before a folder is picked it points to the start page", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/arcanus")
      assert has_element?(view, "#pick-folder-link[href='/']")
      refute has_element?(view, "#save-slot-1")
    end

    test "with a folder it shows the slots to save to, 1 to 8 only", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/arcanus")
      folder(view, [1, 2, 9])

      for n <- 1..8, do: assert(has_element?(view, "#save-slot-#{n}:not([disabled])"))
      refute has_element?(view, "#save-slot-9")
    end

    test "the unsaved badge is always in the page and shows only when something is unsaved", %{
      conn: conn,
      sid: sid
    } do
      open_save(sid)
      {:ok, view, _} = live(conn, ~p"/arcanus")
      assert has_element?(view, "#unsaved-badge.invisible")

      edit(sid)
      assert badge_shown?(view)
    end

    test "a wizard page edit shows it, on that page", %{conn: conn, sid: sid} do
      open_save(sid)
      {:ok, wizard, _} = live(conn, ~p"/wizard/1")
      assert has_element?(wizard, "#header-wizards a[href='/wizard/1']", "Jafar")
      refute badge_shown?(wizard)

      render_click(wizard, "toggle_edit", %{})
      wizard |> element("#wizard-form") |> render_submit(%{"wizard" => %{"gold" => "5000"}})

      assert SaveManager.unsaved_count(SessionStore.get(sid)) > 0
      assert badge_shown?(wizard)
    end
  end

  describe "saving into a slot" do
    setup %{conn: conn, sid: sid} do
      open_save(sid)
      {:ok, view, _} = live(conn, ~p"/arcanus")
      folder(view, [1, 2])
      %{view: view}
    end

    test "an empty slot is written straight away, without a backup", %{view: view, sid: sid} do
      edit(sid)
      view |> element("#save-slot-5") |> render_click()

      assert_push_event(view, "slots:write", %{slot: 5, data: data, backup: false})
      {:ok, written} = Base.decode64(data)
      assert {:ok, ^written} = SaveManager.slot_bytes(SessionStore.get(sid))
      assert written != raw()

      # nothing is marked saved until the browser says the file is written
      assert badge_shown?(view)

      render_hook(view, "slots:written", %{"slot" => 5})
      refute badge_shown?(view)
      assert has_element?(view, "#slots-status", "Saved to SAVE5.GAM")
      assert SessionStore.get(sid).save_path == "SAVE5.GAM"
      assert SessionStore.get(sid).save.raw == written
    end

    test "the message says when the browser also named the slot in the game's list", %{
      view: view,
      sid: sid
    } do
      edit(sid)
      view |> element("#save-slot-5") |> render_click()
      assert_push_event(view, "slots:write", %{slot: 5})

      render_hook(view, "slots:written", %{"slot" => 5, "named" => "Mirror Edit Slot 5"})
      assert has_element?(view, "#slots-status", "named \"Mirror Edit Slot 5\"")
    end

    test "a full slot asks first, and Cancel writes nothing", %{view: view} do
      view |> element("#save-slot-2") |> render_click()
      assert has_element?(view, "#replace-confirm", "Replace SAVE2.GAM?")
      refute_push_event(view, "slots:write", _)

      view |> element("#cancel-replace") |> render_click()
      refute has_element?(view, "#replace-confirm")
      refute_push_event(view, "slots:write", _)
    end

    test "Replace writes the slot and asks the browser for a backup", %{view: view} do
      view |> element("#save-slot-2") |> render_click()
      view |> element("#confirm-replace") |> render_click()

      assert_push_event(view, "slots:write", %{slot: 2, backup: true})
      refute has_element?(view, "#replace-confirm")
    end

    test "slot 9, the autosave, is never written to", %{view: view} do
      render_hook(view, "slots:save", %{"slot" => "9"})
      assert has_element?(view, "#slots-status", "autosave")
      refute_push_event(view, "slots:write", _)
    end

    test "a failed write leaves the edits marked unsaved", %{view: view, sid: sid} do
      edit(sid)
      view |> element("#save-slot-5") |> render_click()
      assert_push_event(view, "slots:write", %{slot: 5})

      render_hook(view, "slots:error", %{
        "message" => "Could not save SAVE5.GAM, nothing was changed: disk full"
      })

      assert has_element?(view, "#slots-status", "disk full")
      assert badge_shown?(view)

      # and a late "written" for it is ignored
      render_hook(view, "slots:written", %{"slot" => 5})
      assert badge_shown?(view)
    end

    test "an edit made while the file was being written stays unsaved", %{view: view, sid: sid} do
      edit(sid)
      view |> element("#save-slot-5") |> render_click()
      assert_push_event(view, "slots:write", %{slot: 5})

      {:ok, _} =
        SessionStore.update(sid, fn s ->
          %{s | save: %{s.save | raw: WizardFixture.field(s.save.raw, 0, 0x24, <<7, 0>>)}}
        end)

      render_hook(view, "slots:written", %{"slot" => 5})
      assert badge_shown?(view)
    end
  end

  test "saving with nothing open says so", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/arcanus")
    folder(view, [1])
    view |> element("#save-slot-4") |> render_click()
    assert has_element?(view, "#slots-status", "Open a save first")
    refute_push_event(view, "slots:write", _)
  end
end
