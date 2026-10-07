defmodule MirrorWeb.MapLiveEditTest do
  @moduledoc """
  View vs edit mode on the map pages (STORY-016, 022, 023, 026, 027).

  Uses a synthetic save fixture so editing, undo, discard, Save as and Surveyor
  tests run unconditionally in CI without needing game files (STORY-041).
  A handful of real-save tests run only when MIRROR_MOM_PATH contains a real save (SAVE1.GAM).
  """
  use MirrorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @mom_path System.get_env("MIRROR_MOM_PATH")
  @real_save_source @mom_path && Path.join(@mom_path, "SAVE1.GAM")
  @has_real_save @real_save_source && File.exists?(@real_save_source)
  @has_real_save_and_sprites @has_real_save &&
                               File.exists?(Path.join(@mom_path, "MAPBACK.LBX")) &&
                               File.exists?(Path.join(@mom_path, "UNITS1.LBX")) &&
                               File.exists?(Path.join(@mom_path, "UNITS2.LBX"))

  setup %{conn: conn} do
    dir = Path.join(System.tmp_dir!(), "mirror-edit-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    save = Path.join(dir, "SAVE1.GAM")
    File.write!(save, synthetic_save_bytes())
    on_exit(fn -> File.rm_rf!(dir) end)

    conn =
      init_test_session(conn, %{"mirror_session_id" => "edit-test-#{System.unique_integer()}"})

    %{conn: conn, dir: dir, save: save}
  end

  # Open the map, load the save, enter edit mode with the given tool.
  defp editing(conn, save, tool \\ "cycle") do
    {:ok, view, _} = live(conn, ~p"/arcanus")
    view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})
    render_click(view, "toggle_edit", %{})
    render_click(view, "set_tool", %{"tool" => tool})
    view
  end

  defp reopen_in_edit(conn) do
    {:ok, view, _} = live(conn, ~p"/arcanus")
    render_click(view, "toggle_edit", %{})
    view
  end

  defp changed(view), do: view |> element("#changed-tiles") |> render() |> text_of()

  defp text_of(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.text() |> String.trim()

  defp pointer(view, action, x, y, opts \\ []) do
    render_hook(view, "map_pointer", %{
      "action" => action,
      "x" => x,
      "y" => y,
      "button" => Keyword.get(opts, :button, 0),
      "mods" => %{"shift" => Keyword.get(opts, :shift, false)}
    })
  end

  defp click(view, x, y, opts \\ []) do
    pointer(view, "start", x, y, opts)
    pointer(view, "end", x, y, opts)
  end

  # Current tile number at (x, y), read from the hover readout.
  defp tile_at(view, x, y) do
    pointer(view, "hover", x, y)
    [_, n] = Regex.run(~r/tile (\d+)/, view |> element("#hover-readout") |> render() |> text_of())
    String.to_integer(n)
  end

  defp paint(view, x, y, tile) do
    render_click(view, "set_tool", %{"tool" => "paint"})
    view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "#{tile}"}})
    click(view, x, y)
  end

  describe "view mode" do
    test "ignores paint and wheel input", %{conn: conn, save: save} do
      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})

      click(view, 1, 1)
      pointer(view, "drag", 2, 1)
      render_hook(view, "map_pointer", %{"action" => "wheel", "delta" => -100, "mods" => %{}})

      refute has_element?(view, "#unsaved-notice")
      assert changed(reopen_in_edit(conn)) =~ "0 tiles changed"
    end

    test "a reload never lands in edit mode, but keeps the draft (STORY-026)",
         %{conn: conn, save: save} do
      view = editing(conn, save)
      click(view, 1, 1)

      {:ok, reloaded, _} = live(conn, ~p"/arcanus?edit=terrain")
      refute has_element?(reloaded, "#edit-toolbar")
      assert reloaded |> element("#unsaved-notice") |> render() =~ "1 unsaved change"
    end

    test "the unsaved notice can discard, with an in-page confirm", %{conn: conn, save: save} do
      view = editing(conn, save)
      click(view, 1, 1)
      render_click(view, "toggle_edit", %{})

      render_click(view, "arm_discard", %{})
      assert has_element?(view, "#confirm-discard-button")
      render_click(view, "discard_edits", %{})
      refute has_element?(view, "#unsaved-notice")
    end

    test "discard terminates superseded engine session (STORY-039)", %{conn: conn, save: save} do
      session_id = "engine-term-test-#{System.unique_integer([:positive])}"
      conn = init_test_session(conn, %{"mirror_session_id" => session_id})
      view = editing(conn, save, "cycle")

      state = Mirror.SessionStore.get(session_id)
      old_engine_id = state.engine_session_id
      assert old_engine_id != nil
      old_pid = Mirror.Engine.Session.whereis(old_engine_id)
      assert Process.alive?(old_pid)

      click(view, 1, 1)
      render_click(view, "arm_discard", %{})
      render_click(view, "discard_edits", %{})

      refute Process.alive?(old_pid)

      new_engine_id = Mirror.SessionStore.get(session_id).engine_session_id
      assert new_engine_id != nil
      assert new_engine_id != old_engine_id
      new_pid = Mirror.Engine.Session.whereis(new_engine_id)
      assert Process.alive?(new_pid)
    end
  end

  describe "multi-tab session synchronization (STORY-039)" do
    test "two tabs on one session sync edits without overwriting", %{conn: conn, save: save} do
      session_id = "two-tab-test-#{System.unique_integer([:positive])}"
      conn1 = init_test_session(conn, %{"mirror_session_id" => session_id})
      conn2 = init_test_session(conn, %{"mirror_session_id" => session_id})

      {:ok, tab1, _} = live(conn1, ~p"/arcanus")
      tab1 |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})

      {:ok, tab2, _} = live(conn2, ~p"/arcanus")

      # Tab 1 enters edit mode and paints a tile
      render_click(tab1, "toggle_edit", %{})
      render_click(tab1, "set_tool", %{"tool" => "cycle"})
      click(tab1, 1, 1)

      assert changed(tab1) =~ "1 tile changed"

      # Tab 2 receives the synchronized state
      render_click(tab2, "toggle_edit", %{})
      assert changed(tab2) =~ "1 tile changed"

      # Tab 2 changes tool (writing to SessionStore)
      render_click(tab2, "set_tool", %{"tool" => "paint"})

      # Verify Tab 1's edit was preserved in SessionStore and in both tabs
      assert changed(tab2) =~ "1 tile changed"
      assert changed(tab1) =~ "1 tile changed"
    end

    test "competing concurrent edits from two tabs with same starting state both survive (STORY-039)",
         %{conn: conn, save: save} do
      session_id = "competing-tab-test-#{System.unique_integer([:positive])}"
      conn1 = init_test_session(conn, %{"mirror_session_id" => session_id})
      conn2 = init_test_session(conn, %{"mirror_session_id" => session_id})

      {:ok, tab1, _} = live(conn1, ~p"/arcanus")
      tab1 |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})

      {:ok, tab2, _} = live(conn2, ~p"/arcanus")

      # Both tabs enter edit mode with cycle tool
      render_click(tab1, "toggle_edit", %{})
      render_click(tab1, "set_tool", %{"tool" => "cycle"})
      render_click(tab2, "toggle_edit", %{})
      render_click(tab2, "set_tool", %{"tool" => "cycle"})

      # Both tabs start from the same baseline state (0 edits)
      assert changed(tab1) =~ "0 tiles changed"
      assert changed(tab2) =~ "0 tiles changed"

      # Both tabs execute edits concurrently without waiting on each other's broadcast
      t1 = Task.async(fn -> click(tab1, 1, 1) end)
      t2 = Task.async(fn -> click(tab2, 2, 2) end)
      Task.await(t1)
      Task.await(t2)

      # Both edits survive in the synchronized SessionStore and in both tabs
      state = Mirror.SessionStore.get(session_id)
      plane = state.planes.arcanus.terrain

      assert Mirror.Map.get_tile_u16_le(plane, 1, 1) !=
               Mirror.Map.get_tile_u16_le(state.original_planes.arcanus.terrain, 1, 1)

      assert Mirror.Map.get_tile_u16_le(plane, 2, 2) !=
               Mirror.Map.get_tile_u16_le(state.original_planes.arcanus.terrain, 2, 2)

      assert changed(tab1) =~ "2 tiles changed"
      assert changed(tab2) =~ "2 tiles changed"
    end

    test "saving from a tab with stale socket state preserves concurrent edits from another tab (STORY-043)",
         %{conn: conn, dir: dir, save: save} do
      session_id = "stale-save-test-#{System.unique_integer([:positive])}"
      conn1 = init_test_session(conn, %{"mirror_session_id" => session_id})

      {:ok, tab1, _} = live(conn1, ~p"/arcanus")
      tab1 |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})
      render_click(tab1, "toggle_edit", %{})
      render_click(tab1, "set_tool", %{"tool" => "cycle"})
      click(tab1, 1, 1)
      assert changed(tab1) =~ "1 tile changed"

      # Simulate Tab B committing an edit directly into SessionStore (e.g. before Tab 1's broadcast arrives)
      current_store = Mirror.SessionStore.get(session_id)
      tab1_edited_val = Mirror.Map.get_tile_u16_le(current_store.planes.arcanus.terrain, 1, 1)
      baseline_at_2_2 = Mirror.Map.get_tile_u16_le(current_store.planes.arcanus.terrain, 2, 2)
      tab2_edited_val = Integer.mod(baseline_at_2_2 + 10, 762)

      {tab2_state, _change, _updates} =
        Mirror.Editor.apply_tile(current_store, :arcanus, :terrain, 2, 2, tab2_edited_val)

      :ets.insert(:mirror_sessions, {session_id, tab2_state})

      # Tab 1 now submits save to SAVE2.GAM with its stale socket assigns
      target_save = Path.join(dir, "SAVE2.GAM")
      tab1 |> element("#save-form") |> render_submit(%{"save" => %{"path" => target_save}})

      # Both Tab 1's edit at (1, 1) and Tab 2's edit at (2, 2) must survive in SessionStore
      store_after = Mirror.SessionStore.get(session_id)

      assert Mirror.Map.get_tile_u16_le(store_after.planes.arcanus.terrain, 1, 1) ==
               tab1_edited_val

      assert Mirror.Map.get_tile_u16_le(store_after.planes.arcanus.terrain, 2, 2) ==
               tab2_edited_val

      # Both edits must survive in the file written to disk
      assert File.exists?(target_save)
      {:ok, loaded_save} = Mirror.SaveFile.load(target_save)

      assert Mirror.Map.get_tile_u16_le(loaded_save.planes.arcanus.terrain, 1, 1) ==
               tab1_edited_val

      assert Mirror.Map.get_tile_u16_le(loaded_save.planes.arcanus.terrain, 2, 2) ==
               tab2_edited_val
    end

    test "stroke resolves brush value from current session store even if tab socket selection is stale (STORY-043)",
         %{conn: conn, save: save} do
      session_id = "stale-brush-test-#{System.unique_integer([:positive])}"
      conn1 = init_test_session(conn, %{"mirror_session_id" => session_id})

      {:ok, tab1, _} = live(conn1, ~p"/arcanus")
      tab1 |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})
      render_click(tab1, "toggle_edit", %{})
      render_click(tab1, "set_tool", %{"tool" => "paint"})

      # Simulate Tab B updating the active brush selection in SessionStore
      # without Tab 1 having processed the broadcast
      current_store = Mirror.SessionStore.get(session_id)
      updated_selection = Map.put(current_store.selection, :terrain, 42)
      :ets.insert(:mirror_sessions, {session_id, %{current_store | selection: updated_selection}})

      # Tab 1 starts painting at (3, 3)
      pointer(tab1, "start", 3, 3)
      pointer(tab1, "end", 3, 3)

      # The painted tile must be 42 from the authoritative current session
      store_after = Mirror.SessionStore.get(session_id)
      assert Mirror.Map.get_tile_u16_le(store_after.planes.arcanus.terrain, 3, 3) == 42
    end

    test "concurrent stroke continuation preserves interleaved stroke from another tab (STORY-043)",
         %{conn: conn, save: save} do
      session_id = "concurrent-drag-stroke-test-#{System.unique_integer([:positive])}"
      conn1 = init_test_session(conn, %{"mirror_session_id" => session_id})
      conn2 = init_test_session(conn, %{"mirror_session_id" => session_id})

      {:ok, tab1, _} = live(conn1, ~p"/arcanus")
      tab1 |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})
      render_click(tab1, "toggle_edit", %{})
      render_click(tab1, "set_tool", %{"tool" => "paint"})

      {:ok, tab2, _} = live(conn2, ~p"/arcanus")
      render_click(tab2, "toggle_edit", %{})
      render_click(tab2, "set_tool", %{"tool" => "cycle"})

      # Baseline value at (5, 5)
      start_store = Mirror.SessionStore.get(session_id)
      baseline_at_5_5 = Mirror.Map.get_tile_u16_le(start_store.planes.arcanus.terrain, 5, 5)

      # Tab 1 starts a drag stroke (pointer start at 1, 1 then drag to 1, 2)
      pointer(tab1, "start", 1, 1)
      pointer(tab1, "drag", 1, 2)

      # Tab 2 commits a separate single-tile cycle stroke at (5, 5) in between Tab 1's moves
      click(tab2, 5, 5)

      # Tab 1 continues drag to (1, 3) and ends stroke
      pointer(tab1, "drag", 1, 3)
      pointer(tab1, "end", 1, 3)

      # Both Tab 1's drag tiles and Tab 2's cycle tile are present
      store_after = Mirror.SessionStore.get(session_id)

      assert Mirror.Map.get_tile_u16_le(store_after.planes.arcanus.terrain, 5, 5) ==
               Integer.mod(baseline_at_5_5 + 1, 762)

      # Undoing once in Tab 1 pops Tab 2's stroke (the head of history)
      render_click(tab1, "undo", %{})

      store_after_undo = Mirror.SessionStore.get(session_id)
      # Tab 2's tile was undone back to baseline
      assert Mirror.Map.get_tile_u16_le(store_after_undo.planes.arcanus.terrain, 5, 5) ==
               baseline_at_5_5

      # Tab 1's drag tiles (1, 1), (1, 2), (1, 3) are still intact
      brush_val = Map.get(start_store.selection, :terrain, 0)

      assert Mirror.Map.get_tile_u16_le(store_after_undo.planes.arcanus.terrain, 1, 1) ==
               brush_val

      assert Mirror.Map.get_tile_u16_le(store_after_undo.planes.arcanus.terrain, 1, 2) ==
               brush_val

      assert Mirror.Map.get_tile_u16_le(store_after_undo.planes.arcanus.terrain, 1, 3) ==
               brush_val
    end
  end

  describe "Cycle tool (STORY-027)" do
    test "click steps the tile +1; right-click and shift-click step back",
         %{conn: conn, save: save} do
      view = editing(conn, save)
      start = tile_at(view, 5, 5)

      click(view, 5, 5)
      assert tile_at(view, 5, 5) == Integer.mod(start + 1, 762)
      click(view, 5, 5)
      assert tile_at(view, 5, 5) == Integer.mod(start + 2, 762)

      click(view, 5, 5, button: 2)
      assert tile_at(view, 5, 5) == Integer.mod(start + 1, 762)
      click(view, 5, 5, shift: true)
      assert tile_at(view, 5, 5) == start
    end

    test "wraps at both ends", %{conn: conn, save: save} do
      view = editing(conn, save)
      paint(view, 6, 6, 761)
      render_click(view, "set_tool", %{"tool" => "cycle"})

      click(view, 6, 6)
      assert tile_at(view, 6, 6) == 0
      click(view, 6, 6, button: 2)
      assert tile_at(view, 6, 6) == 761
    end

    test "undo and redo of a painted type revert terrain and landmass together, and push both layers",
         %{conn: conn, save: save} do
      session_id = "paint-type-undo-test-#{System.unique_integer([:positive])}"
      conn = init_test_session(conn, %{"mirror_session_id" => session_id})

      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})
      render_click(view, "toggle_edit", %{})

      before = Mirror.SessionStore.get(session_id)

      cells = Mirror.TerrainPaint.brush_cells(30, 20, 3)

      {:ok, painted, {:applied, _entry, layers}} =
        Mirror.SessionStore.update(session_id, fn current ->
          {next, outcome, _report} = Mirror.Editor.paint_type(current, :arcanus, cells, :grass)
          {next, outcome}
        end)

      assert Enum.map(layers, & &1.layer) == [:terrain, :landmass]
      assert painted.planes.arcanus.landmass != before.planes.arcanus.landmass

      render_click(view, "undo", %{})
      assert_push_event(view, "engine_delta", %{layer: "terrain"})
      assert_push_event(view, "engine_delta", %{layer: "landmass"})

      undone = Mirror.SessionStore.get(session_id)
      assert undone.planes == before.planes
      assert undone.history.arcanus == []

      render_click(view, "redo", %{})
      assert_push_event(view, "engine_delta", %{layer: "terrain"})
      assert_push_event(view, "engine_delta", %{layer: "landmass"})

      redone = Mirror.SessionStore.get(session_id)
      assert redone.planes == painted.planes
    end

    test "each click is one undo step, pushed live", %{conn: conn, save: save} do
      view = editing(conn, save)
      start = tile_at(view, 7, 7)

      click(view, 7, 7)
      assert_push_event(view, "engine_delta", %{changes: [%{x: 7, y: 7}]})
      click(view, 7, 7)

      render_click(view, "undo", %{})
      assert tile_at(view, 7, 7) == Integer.mod(start + 1, 762)
      render_click(view, "undo", %{})
      assert tile_at(view, 7, 7) == start
    end

    test "undo and redo keep research statistics in sync (STORY-039)", %{conn: conn, save: save} do
      {:ok, dataset_id} = Mirror.Stats.dataset_id_from_path(save)
      view = editing(conn, save, "cycle")

      before_hist = Mirror.Stats.histogram(dataset_id, :computed_adj_mask, :global)
      before_rays = ray_observations(dataset_id)

      click(view, 5, 5)
      after_click_hist = Mirror.Stats.histogram(dataset_id, :computed_adj_mask, :global)
      after_click_rays = ray_observations(dataset_id)
      assert after_click_hist != before_hist
      assert after_click_rays != before_rays

      render_click(view, "undo", %{})
      after_undo_hist = Mirror.Stats.histogram(dataset_id, :computed_adj_mask, :global)
      after_undo_rays = ray_observations(dataset_id)
      assert after_undo_hist == before_hist
      assert after_undo_rays == before_rays

      render_click(view, "redo", %{})
      after_redo_hist = Mirror.Stats.histogram(dataset_id, :computed_adj_mask, :global)
      after_redo_rays = ray_observations(dataset_id)
      assert after_redo_hist == after_click_hist
      assert after_redo_rays == after_click_rays
    end
  end

  describe "Paint tool" do
    test "paints, undoes and redoes", %{conn: conn, save: save} do
      view = editing(conn, save, "paint")
      view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "5"}})

      click(view, 1, 1)
      assert changed(view) =~ "1 tile changed"

      render_click(view, "undo", %{})
      assert changed(view) =~ "0 tiles changed"

      render_click(view, "redo", %{})
      assert changed(view) =~ "1 tile changed"
    end

    test "painting, undo and redo push the tile to the canvas (STORY-023)",
         %{conn: conn, save: save} do
      view = editing(conn, save, "paint")
      view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "5"}})

      pointer(view, "start", 1, 1)

      assert_push_event(view, "engine_delta", %{
        layer: "terrain",
        changes: [%{x: 1, y: 1, new: 5}]
      })

      pointer(view, "end", 1, 1)

      render_click(view, "undo", %{})

      assert_push_event(view, "engine_delta", %{
        layer: "terrain",
        changes: [%{x: 1, y: 1, prev: 5}]
      })

      render_click(view, "redo", %{})

      assert_push_event(view, "engine_delta", %{
        layer: "terrain",
        changes: [%{x: 1, y: 1, new: 5}]
      })
    end

    test "terrain edits push recomputed adjacency masks to client (STORY-039)",
         %{conn: conn, save: save} do
      view = editing(conn, save, "paint")
      view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "5"}})

      pointer(view, "start", 1, 1)

      assert_push_event(view, "engine_delta", %{
        layer: "computed_adj_mask",
        changes: adj_changes
      })

      assert Enum.any?(adj_changes, &match?(%{x: 1, y: 1}, &1))
    end

    test "a stroke is undoable even if it never finishes", %{conn: conn, save: save} do
      view = editing(conn, save, "paint")
      view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "5"}})

      pointer(view, "start", 3, 3)
      pointer(view, "drag", 4, 3)
      # No "end": the LiveView goes away mid-stroke (reload, crash, navigation).

      again = reopen_in_edit(conn)
      assert changed(again) =~ "2 tiles changed"
      render_click(again, "undo", %{})
      assert changed(again) =~ "0 tiles changed"
    end

    test "brush is clamped to real tile numbers", %{conn: conn, save: save} do
      view = editing(conn, save, "paint")
      html = view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "99999"}})
      assert html =~ ~s(value="761")
    end

    test "a drag starting on a matching tile paints subsequent tiles (STORY-039)",
         %{conn: conn, save: save} do
      view = editing(conn, save, "paint")
      start_1_1 = tile_at(view, 1, 1)

      view |> element("#brush-form") |> render_change(%{"brush" => %{"tile" => "#{start_1_1}"}})

      pointer(view, "start", 1, 1)
      pointer(view, "drag", 2, 1)
      pointer(view, "end", 2, 1)

      assert tile_at(view, 2, 1) == start_1_1
      assert changed(view) =~ "1 tile changed"

      render_click(view, "undo", %{})
      assert changed(view) =~ "0 tiles changed"
    end
  end

  test "save as refuses the loaded file, writes a new one, and discard restores",
       %{conn: conn, dir: dir, save: save} do
    view = editing(conn, save)
    original = File.read!(save)
    click(view, 1, 1)

    html = view |> element("#save-form") |> render_submit(%{"save" => %{"path" => save}})
    assert html =~ "won&#39;t overwrite"
    assert File.read!(save) == original

    target = Path.join(dir, "SAVE2.GAM")
    view |> element("#save-form") |> render_submit(%{"save" => %{"path" => target}})
    assert File.exists?(target)
    assert File.read!(target) != original
    assert changed(view) =~ "0 tiles changed"

    click(view, 2, 2)
    assert changed(view) =~ "1 tile changed"
    render_click(view, "arm_discard", %{})
    render_click(view, "discard_edits", %{})
    assert changed(view) =~ "0 tiles changed"
  end

  test "after Save as, discard reloads engine from last-saved planes (STORY-039)",
       %{conn: conn, dir: dir, save: save} do
    view = editing(conn, save)
    start_1_1 = tile_at(view, 1, 1)
    click(view, 1, 1)
    saved_tile_1_1 = tile_at(view, 1, 1)
    assert saved_tile_1_1 != start_1_1

    target = Path.join(dir, "SAVE2.GAM")
    view |> element("#save-form") |> render_submit(%{"save" => %{"path" => target}})

    # Paint another tile after Save as
    click(view, 2, 2)
    assert changed(view) =~ "1 tile changed"

    # Discard edits: should restore to SAVE2.GAM planes, and hover inspection must match
    render_click(view, "arm_discard", %{})
    render_click(view, "discard_edits", %{})
    assert changed(view) =~ "0 tiles changed"

    assert tile_at(view, 1, 1) == saved_tile_1_1
  end

  describe "cities overlay (STORY-010)" do
    test "loading a save pushes this plane's cities with owner banners", %{conn: conn, save: save} do
      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})

      assert_push_event(view, "overlay_data", %{layer: "cities", items: items})
      assert length(items) == 16
      assert %{x: 38, y: 21, frame: 0, banner: :yellow, name: "Deventor", walled: false} in items
    end

    test "the hover readout names the city under the pointer (STORY-032)", %{
      conn: conn,
      save: save
    } do
      # City Walls for record 0 (Deventor): byte +66 of the block at 0x8aac.
      File.write!(save, put_byte(File.read!(save), 0x8AAC + 66, 1))

      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})

      assert_push_event(view, "overlay_data", %{layer: "cities", items: items})
      assert %{name: "Deventor", walled: true} = Enum.find(items, &(&1.name == "Deventor"))

      pointer(view, "hover", 38, 21)

      assert view |> element("#hover-city") |> render() |> text_of() =~
               ~r/Deventor\s+\(Hamlet, walled\)/

      pointer(view, "hover", 0, 0)
      refute has_element?(view, "#hover-city")
    end

    test "computes frame from population thresholds (STORY-033)", %{conn: conn, dir: dir} do
      save_with_pops = Path.join(dir, "CITIES_POPS_TEST.GAM")
      raw = synthetic_save_bytes()

      # The 16 cities start at 0x8AAC, each 114 bytes. Byte +20 is population.
      # We'll update the first 10 cities to have the specific populations.
      pops = [1, 4, 5, 8, 9, 12, 13, 16, 17, 25]
      expected_frames = [0, 0, 1, 1, 2, 2, 3, 3, 4, 4]

      raw =
        pops
        |> Enum.with_index()
        |> Enum.reduce(raw, fn {pop, i}, acc ->
          offset = 0x8AAC + i * 114
          put_byte(acc, offset + 20, pop)
        end)

      File.write!(save_with_pops, raw)

      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save_with_pops}})

      assert_push_event(view, "overlay_data", %{layer: "cities", items: items})

      frames =
        items
        |> Enum.take(10)
        |> Enum.map(& &1.frame)

      assert frames == expected_frames
    end
  end

  describe "Surveyor (STORY-034)" do
    test "hovering shows the tile, what's on it, and City Resources or why not", %{
      conn: conn,
      save: save
    } do
      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})

      pointer(view, "hover", 38, 21)
      card = view |> element("#surveyor") |> render() |> text_of()
      assert card =~ ~r/Hills\s*1\/2 food\s*\+3% production\s*Hamlet of\s*Deventor/

      assert card =~
               ~r/City Resources\s*Maximum Pop\s*\d+\s*Prod Bonus\s*\+\d+%\s*Gold Bonus\s*\+\d+%/

      pointer(view, "hover", 39, 20)

      assert view |> element("#surveyor") |> render() |> text_of() =~
               ~r/Mountain\s*\+5% production\s*Gold Ore\s*\+3 gold\s*Cities cannot be built less than 3 squares/

      pointer(view, "hover", 0, 0)
      assert view |> element("#surveyor") |> render() |> text_of() =~ ~r/Surveyor\s*Unexplored/
    end

    test "is a view-mode tool: edit mode hides it", %{conn: conn, save: save} do
      view = editing(conn, save)
      pointer(view, "hover", 38, 21)
      refute has_element?(view, "#surveyor")
    end
  end

  describe "settleable tiles, roads, and fog layers (STORY-013, STORY-035, STORY-036)" do
    test "overlays are pushed with the map and follow edits", %{
      conn: conn,
      save: save
    } do
      {:ok, view, html} = live(conn, ~p"/arcanus")
      refute html =~ ~r/value="fog"[^>]*checked/
      refute html =~ ~r/value="settleable"[^>]*checked/
      assert html =~ ~r/value="roads"[^>]*checked/
      assert html =~ ~r/value="cities"[^>]*checked/
      assert html =~ ~r/value="units"[^>]*checked/

      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})

      assert_push_event(view, "overlay_data", %{layer: "units", items: []})

      assert_push_event(view, "overlay_data", %{layer: "settleable", items: settleable})
      refute Enum.any?(settleable, &match?(%{x: 38, y: 21}, &1))
      assert Enum.all?(settleable, &(&1.max_pop in 0..25))

      # STORY-013: roads, specials and corruption
      assert_push_event(view, "overlay_data", %{layer: "roads", items: roads})

      assert %{kind: :special, x: 39, y: 20, special: :gold} =
               Enum.find(roads, &match?(%{x: 39, y: 20}, &1))

      # SAVE1 is turn one: most of the map is fog; 15 is fully explored.
      assert_push_event(view, "overlay_data", %{layer: "fog", items: fog})
      assert %{explored: 0} = Enum.find(fog, &match?(%{x: 0, y: 0}, &1))
      refute Enum.any?(fog, &match?(%{x: 38, y: 21}, &1))

      render_click(view, "toggle_edit", %{})
      render_click(view, "set_tool", %{"tool" => "cycle"})
      pointer(view, "start", 10, 10)
      assert_push_event(view, "overlay_data", %{layer: "settleable"})
      assert_push_event(view, "overlay_data", %{layer: "roads"})
    end

    test "discard refreshes settleable, roads, and fog overlays (STORY-039)", %{
      conn: conn,
      save: save
    } do
      view = editing(conn, save, "cycle")
      pointer(view, "start", 10, 10)
      assert_push_event(view, "overlay_data", %{layer: "settleable"})
      assert_push_event(view, "overlay_data", %{layer: "roads"})

      render_click(view, "arm_discard", %{})
      render_click(view, "discard_edits", %{})

      assert_push_event(view, "overlay_data", %{layer: "settleable"})
      assert_push_event(view, "overlay_data", %{layer: "roads"})
      assert_push_event(view, "overlay_data", %{layer: "fog"})
    end

    test "pushes visible units with banner colours and collapsed stacks (STORY-012)", %{
      conn: conn,
      dir: dir
    } do
      save_with_units = Path.join(dir, "UNITS_TEST.GAM")
      raw = synthetic_save_bytes()

      # Wizard 1 banner = 0 (Blue) at 0x9E8 + 1 * 0x4C8 + 0x16
      raw = put_bytes(raw, 0x09E8 + 0x4C8 + 0x16, <<0>>)

      # Set unit count = 3 at 0x0009E2
      raw = put_bytes(raw, 0x0009E2, <<3::little-16>>)

      # Unit 0: (25, 25, plane 0), owner 0 (Yellow), type 39, priority 2
      u0 = <<25, 25, 0, 0, 2, 39, 0::size(96), 2, 0::size(104)>>
      # Unit 1: (25, 25, plane 0), owner 1 (Blue), type 40, priority 5
      u1 = <<25, 25, 0, 1, 2, 40, 0::size(96), 5, 0::size(104)>>
      # Unit 2: (38, 21, plane 0) - inside Deventor city -> hidden!
      u2 = <<38, 21, 0, 0, 2, 39, 0::size(96), 1, 0::size(104)>>

      raw = put_bytes(raw, 0x00B734, u0 <> u1 <> u2)
      File.write!(save_with_units, raw)

      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save_with_units}})

      assert_push_event(view, "overlay_data", %{layer: "units", items: items})
      assert length(items) == 1
      [visible] = items
      assert visible == %{x: 25, y: 25, type: 40, banner: :blue}
    end
  end

  describe "overlays follow the save across tabs (STORY-044)" do
    # The newest items pushed for a layer so far (events queue up, so read them all).
    defp latest_overlay(view, layer, last \\ nil) do
      next =
        try do
          assert_push_event(view, "overlay_data", %{layer: ^layer, items: items}, 50)
          items
        rescue
          ExUnit.AssertionError -> :none
        end

      case {next, last} do
        {:none, nil} -> flunk("no #{layer} overlay was pushed")
        {:none, last} -> last
        {items, _} -> latest_overlay(view, layer, items)
      end
    end

    # Reads and drops every queued push of an event.
    defp drain(view, event) do
      assert_push_event(view, event, _, 50)
      drain(view, event)
    rescue
      ExUnit.AssertionError -> :ok
    end

    defp two_tabs(conn) do
      session_id = "overlay-tabs-#{System.unique_integer([:positive])}"
      conn1 = init_test_session(conn, %{"mirror_session_id" => session_id})
      conn2 = init_test_session(conn, %{"mirror_session_id" => session_id})
      {:ok, tab1, _} = live(conn1, ~p"/arcanus")
      {:ok, tab2, _} = live(conn2, ~p"/arcanus")
      {tab1, tab2}
    end

    defp load(view, path),
      do: view |> element("#load-form") |> render_submit(%{"load" => %{"path" => path}})

    test "a save loaded in one tab shows its cities, units and sites in the other", %{
      conn: conn,
      save: save
    } do
      {tab1, tab2} = two_tabs(conn)
      load(tab1, save)

      assert Enum.any?(latest_overlay(tab2, "cities"), &match?(%{name: "Deventor"}, &1))
      assert latest_overlay(tab2, "units") == []
      assert Enum.any?(latest_overlay(tab2, "sites"), &match?(%{x: 48, y: 28}, &1))
    end

    test "loading a different save replaces the other tab's overlays", %{
      conn: conn,
      dir: dir,
      save: save
    } do
      other = Path.join(dir, "SAVE2.GAM")
      File.write!(other, String.replace(File.read!(save), "Deventor", "Deventer"))

      {tab1, tab2} = two_tabs(conn)
      load(tab1, save)
      assert Enum.any?(latest_overlay(tab2, "cities"), &match?(%{name: "Deventor"}, &1))

      load(tab1, other)
      cities = latest_overlay(tab2, "cities")
      assert Enum.any?(cities, &match?(%{name: "Deventer"}, &1))
      refute Enum.any?(cities, &match?(%{name: "Deventor"}, &1))
    end

    # Whether the tab has been given the overlay sprites and tile assets yet.
    defp primed?(view), do: :sys.get_state(view.pid).socket.assigns.overlays_primed

    test "a tab opened before any save is set up like a load by the first cross-tab load",
         %{conn: conn, save: save} do
      session_id = "overlay-prime-#{System.unique_integer([:positive])}"
      conn = init_test_session(conn, %{"mirror_session_id" => session_id})
      {:ok, tab1, _} = live(conn, ~p"/arcanus")
      {:ok, tab2, _} = live(conn, ~p"/arcanus")
      refute primed?(tab2)

      load(tab1, save)
      # Its first update gets the sprites and tile assets (a mount with no save never
      # did) and the items.
      assert primed?(tab2)
      assert Enum.any?(latest_overlay(tab2, "cities"), &match?(%{name: "Deventor"}, &1))

      # A tab opened once a save is loaded is set up at mount.
      {:ok, tab3, _} = live(conn, ~p"/arcanus")
      assert primed?(tab3)
    end

    test "a tile edit in one tab does not re-push the other tab's sprites or items", %{
      conn: conn,
      save: save
    } do
      {tab1, tab2} = two_tabs(conn)
      load(tab1, save)
      latest_overlay(tab2, "cities")
      latest_overlay(tab2, "units")
      latest_overlay(tab2, "sites")
      # With the game files present, the first load also sent the sprites.
      drain(tab2, "overlay_sprites")

      render_click(tab1, "toggle_edit", %{})
      render_click(tab1, "set_tool", %{"tool" => "cycle"})
      click(tab1, 1, 1)

      # The map layers still follow the edit...
      assert_push_event(tab2, "overlay_data", %{layer: "roads"})
      # ...but the sprites (an LBX decode) and the save's items do not move.
      refute_push_event(tab2, "overlay_sprites", _, 100)
      refute_push_event(tab2, "overlay_data", %{layer: "cities"}, 100)
      refute_push_event(tab2, "overlay_data", %{layer: "units"}, 100)
      refute_push_event(tab2, "overlay_data", %{layer: "sites"}, 100)
    end
  end

  describe "Roads, corruption and specials tools (STORY-018)" do
    defp road_at(items, x, y), do: Enum.find(items, &match?(%{kind: :road, x: ^x, y: ^y}, &1))

    # The newest roads overlay pushed so far. Events queue up (the load pushes one
    # too), so read them all and keep the last.
    defp latest_roads(view, last \\ nil) do
      next =
        try do
          assert_push_event(view, "overlay_data", %{layer: "roads", items: items}, 50)
          items
        rescue
          ExUnit.AssertionError -> :none
        end

      case {next, last} do
        {:none, nil} -> flunk("no roads overlay was pushed")
        {:none, last} -> last
        {items, _} -> latest_roads(view, items)
      end
    end

    defp flags_byte(path, x, y) do
      {:ok, io} = File.open(path, [:read, :binary])
      {:ok, <<byte>>} = :file.pread(io, 0x01CBB8 + y * 60 + x, 1)
      File.close(io)
      byte
    end

    test "the Road tool steps none, road, enchanted road, none, and shift-click steps back",
         %{conn: conn, save: save} do
      view = editing(conn, save, "road")

      click(view, 12, 12)
      assert %{enchanted: false} = road_at(latest_roads(view), 12, 12)
      assert view |> element("#road-report") |> render() |> text_of() == "Road"

      click(view, 12, 12)
      assert %{enchanted: true} = road_at(latest_roads(view), 12, 12)
      assert view |> element("#road-report") |> render() |> text_of() == "Enchanted road"

      click(view, 12, 12)
      assert road_at(latest_roads(view), 12, 12) == nil

      click(view, 12, 12, shift: true)
      assert %{enchanted: true} = road_at(latest_roads(view), 12, 12)
    end

    test "neighbouring roads redraw as one connected road, ocean included", %{
      conn: conn,
      save: save
    } do
      view = editing(conn, save, "road")
      click(view, 12, 12)
      click(view, 13, 12)

      items = latest_roads(view)
      assert :e in road_at(items, 12, 12).pieces
      assert :w in road_at(items, 13, 12).pieces

      render_click(view, "undo", %{})
      items = latest_roads(view)
      assert road_at(items, 13, 12) == nil
      assert road_at(items, 12, 12).pieces == [:c]
    end

    test "the Corruption tool toggles a tile and leaves its road alone", %{
      conn: conn,
      save: save
    } do
      view = editing(conn, save, "road")
      click(view, 20, 20)
      render_click(view, "set_tool", %{"tool" => "corruption"})

      click(view, 20, 20)
      items = latest_roads(view)
      assert Enum.any?(items, &match?(%{kind: :corruption, x: 20, y: 20}, &1))
      assert road_at(items, 20, 20)

      click(view, 20, 20)
      items = latest_roads(view)
      refute Enum.any?(items, &match?(%{kind: :corruption}, &1))
      assert road_at(items, 20, 20)
    end

    test "the Special tool places the chosen special, and right-click removes it", %{
      conn: conn,
      save: save
    } do
      view = editing(conn, save, "special")
      view |> element("#special-form") |> render_change(%{"special" => %{"value" => "6"}})

      click(view, 14, 14)
      items = latest_roads(view)
      assert Enum.any?(items, &match?(%{kind: :special, x: 14, y: 14, special: :mithril}, &1))
      assert view |> element("#road-report") |> render() |> text_of() == "Mithril ore"

      click(view, 14, 14, button: 2)
      items = latest_roads(view)
      refute Enum.any?(items, &match?(%{kind: :special, x: 14, y: 14}, &1))

      render_click(view, "undo", %{})
      items = latest_roads(view)
      assert Enum.any?(items, &match?(%{kind: :special, x: 14, y: 14, special: :mithril}, &1))
    end

    test "a special the form does not know is ignored", %{conn: conn, save: save} do
      view = editing(conn, save, "special")
      view |> element("#special-form") |> render_change(%{"special" => %{"value" => "6"}})
      view |> element("#special-form") |> render_change(%{"special" => %{"value" => "99"}})

      click(view, 15, 15)
      assert Enum.any?(latest_roads(view), &match?(%{kind: :special, special: :mithril}, &1))
    end

    test "clicking where nothing would change adds no undo step", %{conn: conn, save: save} do
      view = editing(conn, save, "special")
      click(view, 16, 16, button: 2)
      assert changed(view) =~ "0 tiles changed"
    end

    test "edits are counted, survive Save as, and discard restores", %{
      conn: conn,
      dir: dir,
      save: save
    } do
      view = editing(conn, save, "road")
      click(view, 30, 5)
      assert changed(view) =~ "1 tile changed"

      target = Path.join(dir, "SAVE3.GAM")
      view |> element("#save-form") |> render_submit(%{"save" => %{"path" => target}})
      assert flags_byte(target, 30, 5) == 0x08
      assert flags_byte(save, 30, 5) == 0x00

      click(view, 30, 5)
      assert changed(view) =~ "1 tile changed"
      render_click(view, "arm_discard", %{})
      render_click(view, "discard_edits", %{})
      assert %{enchanted: false} = road_at(latest_roads(view), 30, 5)
    end

    test "a click edits the stored byte, so another tab's bit is not erased (STORY-039)", %{
      conn: conn,
      save: save
    } do
      session_id = "stale-flags-test-#{System.unique_integer([:positive])}"
      conn1 = init_test_session(conn, %{"mirror_session_id" => session_id})

      {:ok, tab1, _} = live(conn1, ~p"/arcanus")
      tab1 |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})
      render_click(tab1, "toggle_edit", %{})
      render_click(tab1, "set_tool", %{"tool" => "road"})

      # Another tab corrupts (3, 3) in the session store; this tab has not seen it.
      store = Mirror.SessionStore.get(session_id)
      {flags, 0} = Mirror.Map.put_tile_u8(store.planes.arcanus.terrain_flags, 3, 3, 0x20)

      :ets.insert(
        :mirror_sessions,
        {session_id, put_in(store.planes.arcanus.terrain_flags, flags)}
      )

      click(tab1, 3, 3)

      after_click = Mirror.SessionStore.get(session_id)
      assert Mirror.Map.get_tile_u8(after_click.planes.arcanus.terrain_flags, 3, 3) == 0x28
    end

    test "view mode ignores the tools", %{conn: conn, save: save} do
      view = editing(conn, save, "road")
      render_click(view, "toggle_edit", %{})
      click(view, 12, 12)
      refute has_element?(view, "#unsaved-notice")
    end
  end

  describe "sites layer (STORY-011)" do
    # x, y, plane (0 Arcanus, 1 Myrror), intact (1/0), kind -> 24-byte encounter record.
    defp encounter_bytes(x, y, plane, intact, kind) do
      <<x, y, plane, intact, kind>> <> :binary.copy(<<0>>, 10) <> <<0>> <> :binary.copy(<<0>>, 8)
    end

    test "overlays are pushed with the map and follow edits", %{conn: conn, dir: dir} do
      save_with_sites = Path.join(dir, "SITES_TEST.GAM")
      raw = synthetic_save_bytes()

      # Write a tower at 0x6610 (already there: x=48, y=28, owner=255/nil -> unowned)
      # Add an owned tower
      raw = put_bytes(raw, 0x6610 + 4, <<49, 29, 0, 0>>)

      # Encounters at 0x6628, every intact kind that draws a sprite, plus the
      # cases that must NOT draw: cleared, wrong plane, node guardian.
      encounters = [
        # {x, y, plane, intact, kind}
        {26, 25, 0, 1, 7},
        {28, 21, 0, 0, 6},
        {10, 10, 0, 1, 4},
        {11, 11, 0, 1, 8},
        {12, 12, 0, 1, 5},
        {13, 13, 0, 1, 9},
        {14, 14, 0, 1, 10},
        {17, 17, 0, 1, 6},
        {15, 15, 1, 1, 7},
        {16, 16, 0, 1, 3}
      ]

      raw =
        encounters
        |> Enum.with_index()
        |> Enum.reduce(raw, fn {{x, y, plane, intact, kind}, i}, acc ->
          put_bytes(acc, 0x6628 + i * 24, encounter_bytes(x, y, plane, intact, kind))
        end)

      File.write!(save_with_sites, raw)

      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save_with_sites}})

      assert_push_event(view, "overlay_data", %{layer: "sites", items: items})
      assert length(items) == 9

      # Towers: both planes, unconditionally.
      assert %{x: 48, y: 28, sprite: "tower_unowned"} in items
      assert %{x: 49, y: 29, sprite: "tower_owned"} in items

      # Every intact kind on the viewed (Arcanus) plane maps to its sprite.
      assert %{x: 26, y: 25, sprite: "abandoned_keep"} in items
      assert %{x: 10, y: 10, sprite: "mound"} in items
      assert %{x: 11, y: 11, sprite: "mound"} in items
      assert %{x: 12, y: 12, sprite: "ruins"} in items
      assert %{x: 13, y: 13, sprite: "ruins"} in items
      assert %{x: 14, y: 14, sprite: "fallen_temple"} in items
      assert %{x: 17, y: 17, sprite: "ancient_temple"} in items

      # Cleared, wrong-plane, and node-guardian encounters draw nothing.
      refute Enum.any?(items, &(&1.x == 28 and &1.y == 21))
      refute Enum.any?(items, &(&1.x == 15 and &1.y == 15))
      refute Enum.any?(items, &(&1.x == 16 and &1.y == 16))
    end

    test "encounters on the other plane show there instead", %{conn: conn, dir: dir} do
      save_with_sites = Path.join(dir, "SITES_TEST_MYRROR.GAM")
      raw = synthetic_save_bytes()
      raw = put_bytes(raw, 0x6628, encounter_bytes(15, 15, 1, 1, 7))
      File.write!(save_with_sites, raw)

      {:ok, view, _} = live(conn, ~p"/myrror")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save_with_sites}})

      assert_push_event(view, "overlay_data", %{layer: "sites", items: items})
      assert %{x: 15, y: 15, sprite: "abandoned_keep"} in items
    end
  end

  describe "Paint type tool (STORY-017)" do
    # The shared fixture is a forest world with an inconsistent landmass layer, which
    # is no place to watch coastlines form. These tests run on an all-ocean world
    # whose landmass layer is consistent (all zeros).
    setup %{save: save} do
      File.write!(save, ocean_world_bytes())
      :ok
    end

    defp ocean_world_bytes do
      synthetic_save_bytes()
      |> put_bytes(0x002698, :binary.copy(<<0, 0>>, 4800))
      |> put_bytes(0x004D98, :binary.copy(<<0>>, 4800))
    end

    # A tile's type through the hover readout is awkward, so these read tile numbers
    # and check them against Mirror.TerrainType.
    defp type_at(view, x, y), do: Mirror.TerrainType.terrain_type(tile_at(view, x, y))

    defp paint_form(view, params) do
      view |> element("#paint-form") |> render_change(%{"paint" => params})
    end

    defp report(view), do: view |> element("#paint-report") |> render() |> text_of()

    test "the toolbar offers a terrain dropdown, brush sizes and fill", %{conn: conn, save: save} do
      view = editing(conn, save, "type")

      assert has_element?(view, "#tool-type[aria-pressed=true]")
      assert has_element?(view, "#paint-form #paint-kind")
      assert has_element?(view, "#paint-form #paint-size")
      assert has_element?(view, "#paint-form #paint-fill")

      assert view
             |> element("#paint-kind")
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("option")
             |> Enum.count() == 8

      for label <- [
            "Water (ocean)",
            "Grassland",
            "Forest",
            "Hills",
            "Mountains",
            "Desert",
            "Swamp",
            "Tundra"
          ] do
        assert view |> element("#paint-kind") |> render() =~ label
      end

      assert view |> element("#paint-size") |> render() =~ "3 × 3"
      # the raw tile box belongs to the other tool
      refute has_element?(view, "#brush-form")
    end

    test "the status line is a polite live region from the start, so each result is announced",
         %{conn: conn, save: save} do
      view = editing(conn, save, "type")

      assert has_element?(view, "#paint-report[role=status][aria-live=polite]")
      assert report(view) == ""

      click(view, 30, 20)
      assert has_element?(view, "#paint-report[role=status][aria-live=polite]")
      assert report(view) =~ "9 tiles changed"
    end

    test "joining two islands does not claim the landmass layer was repaired", %{
      conn: conn,
      save: save
    } do
      view = editing(conn, save, "type")
      paint_form(view, %{"kind" => "forest", "size" => "5", "fill" => "false"})
      click(view, 20, 20)
      click(view, 28, 20)

      # a one-tile-wide bridge: it renumbers a whole island's landmass IDs, but the layer
      # was fine, so the status must not say it was repaired
      paint_form(view, %{"kind" => "forest", "size" => "1", "fill" => "false"})
      for x <- 23..25, do: click(view, x, 20)

      assert report(view) =~ "tile"
      refute report(view) =~ "landmass"
    end

    test "painting grass over the ocean re-tiles the tiles around it", %{conn: conn, save: save} do
      view = editing(conn, save, "type")
      assert tile_at(view, 30, 20) == 0

      before_neighbours =
        for {dx, dy} <- [{-1, -1}, {0, -1}, {1, -1}, {-1, 0}, {1, 0}, {-1, 1}, {0, 1}, {1, 1}],
            do: tile_at(view, 30 + dx, 20 + dy)

      assert before_neighbours == List.duplicate(0, 8)

      click(view, 30, 20)

      assert tile_at(view, 30, 20) == 162
      assert type_at(view, 30, 20) == :grass

      # the eight tiles around it became coast, and the sea beyond is untouched
      for {dx, dy} <- [{-1, -1}, {0, -1}, {1, -1}, {-1, 0}, {1, 0}, {-1, 1}, {0, 1}, {1, 1}] do
        assert type_at(view, 30 + dx, 20 + dy) == :shore
        assert tile_at(view, 30 + dx, 20 + dy) != 0
      end

      assert tile_at(view, 28, 20) == 0
      assert changed(view) =~ "9 tiles changed"
      assert report(view) =~ "9 tiles changed"
    end

    test "the chosen terrain and brush size are used", %{conn: conn, save: save} do
      view = editing(conn, save, "type")
      paint_form(view, %{"kind" => "forest", "size" => "3", "fill" => "false"})

      click(view, 30, 20)

      for {dx, dy} <- [{0, 0}, {1, 1}, {-1, -1}],
          do: assert(type_at(view, 30 + dx, 20 + dy) == :forest)

      assert type_at(view, 32, 20) == :shore
      assert type_at(view, 34, 20) == :ocean
      # 9 painted tiles and the ring of 16 around them
      assert changed(view) =~ "25 tiles changed"
    end

    test "an option the form does not know is ignored", %{conn: conn, save: save} do
      view = editing(conn, save, "type")
      paint_form(view, %{"kind" => "river", "size" => "4", "fill" => "false"})
      click(view, 30, 20)

      assert type_at(view, 30, 20) == :grass
      assert changed(view) =~ "9 tiles changed"
    end

    test "dragging paints as you go and undoes in one step", %{conn: conn, save: save} do
      view = editing(conn, save, "type")

      pointer(view, "start", 30, 20)
      assert type_at(view, 30, 20) == :grass
      pointer(view, "drag", 31, 20)
      pointer(view, "drag", 32, 20)
      assert type_at(view, 32, 20) == :grass
      pointer(view, "end", 32, 20)

      assert changed(view) =~ "tiles changed"
      refute changed(view) =~ " 0 tiles"

      render_click(view, "undo", %{})
      assert changed(view) =~ "0 tiles changed"
      for x <- 29..33, do: assert(tile_at(view, x, 20) == 0)

      render_click(view, "redo", %{})
      assert type_at(view, 31, 20) == :grass
    end

    test "fill repaints a whole connected area in one step", %{conn: conn, save: save} do
      view = editing(conn, save, "type")

      # An island wider than a 5x5 brush: a 5x5 block plus a 3x3 block touching it, so
      # its east end at x = 35 is out of reach of a brush at (30, 20) (x 28..32).
      paint_form(view, %{"kind" => "forest", "size" => "5", "fill" => "false"})
      click(view, 30, 20)
      paint_form(view, %{"kind" => "forest", "size" => "3", "fill" => "false"})
      click(view, 34, 20)
      assert type_at(view, 35, 20) == :forest

      paint_form(view, %{"kind" => "desert", "size" => "5", "fill" => "true"})
      click(view, 30, 20)

      # the whole island, both blocks, is desert now; the sea around it is not
      for {x, y} <- [{30, 20}, {28, 18}, {32, 22}, {35, 20}, {35, 21}],
          do: assert(type_at(view, x, y) == :desert)

      assert type_at(view, 38, 20) == :ocean

      render_click(view, "undo", %{})
      assert type_at(view, 30, 20) == :forest
      assert type_at(view, 35, 20) == :forest
      render_click(view, "undo", %{})
      render_click(view, "undo", %{})
      assert changed(view) =~ "0 tiles changed"
    end

    test "painting keeps the landmass layer in step, and undo removes it", %{
      conn: conn,
      save: save
    } do
      session_id = "paint-type-landmass-#{System.unique_integer([:positive])}"
      conn = init_test_session(conn, %{"mirror_session_id" => session_id})
      view = editing(conn, save, "type")

      click(view, 30, 20)

      state = Mirror.SessionStore.get(session_id)

      ids =
        for y <- 0..39,
            x <- 0..59,
            id = Mirror.Map.get_tile_u8(state.planes.arcanus.landmass, x, y),
            id != 0,
            do: id

      assert [_one] = Enum.uniq(ids)
      assert length(ids) == 1

      render_click(view, "undo", %{})
      state = Mirror.SessionStore.get(session_id)
      assert state.planes.arcanus.landmass == :binary.copy(<<0>>, 2400)
    end

    test "cells that cannot be painted are reported, not changed", %{conn: conn, save: save} do
      view = editing(conn, save, "type")

      # row 0 is a polar row
      click(view, 10, 0)

      assert changed(view) =~ "0 tiles changed"
      assert report(view) =~ "1 left alone"
      assert tile_at(view, 10, 0) == 0
    end

    test "right-click picks the terrain under the pointer", %{conn: conn, save: save} do
      view = editing(conn, save, "type")
      paint_form(view, %{"kind" => "forest", "size" => "1", "fill" => "false"})
      click(view, 30, 20)
      paint_form(view, %{"kind" => "swamp", "size" => "1", "fill" => "false"})
      assert has_element?(view, "#paint-kind option[selected][value=swamp]")

      click(view, 30, 20, button: 2)

      assert has_element?(view, "#paint-kind option[selected][value=forest]")
      # picking paints nothing
      assert changed(view) =~ "9 tiles changed"

      # open water picks as water
      click(view, 10, 10, button: 2)
      assert has_element?(view, "#paint-kind option[selected][value=water]")
    end

    test "view mode ignores painting", %{conn: conn, save: save} do
      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => save}})
      click(view, 30, 20)
      assert changed(reopen_in_edit(conn)) =~ "0 tiles changed"
    end

    test "the raw tile painter has a quick pick of plain tiles and does not re-tile neighbours",
         %{conn: conn, save: save} do
      view = editing(conn, save, "paint")

      assert has_element?(view, "#quick-tile-form #quick-tile")
      # the visible word is a real label for the dropdown
      assert has_element?(view, "#quick-tile-form label[for=quick-tile]", "Quick")
      html = view |> element("#quick-tile") |> render()
      assert html =~ "Grassland (162)" and html =~ "Ocean (0)" and html =~ "Tundra (167)"

      view |> element("#quick-tile-form") |> render_change(%{"quick" => %{"tile" => "163"}})
      click(view, 5, 5)

      assert tile_at(view, 5, 5) == 163
      # the neighbours are left exactly as they were
      assert tile_at(view, 6, 5) == 0
      assert changed(view) =~ "1 tile changed"
    end

    test "the quick pick ignores anything that is not a tile number", %{conn: conn, save: save} do
      view = editing(conn, save, "paint")
      view |> element("#quick-tile-form") |> render_change(%{"quick" => %{"tile" => ""}})
      click(view, 5, 5)
      assert tile_at(view, 5, 5) != 163
    end
  end

  describe "Paint type tool on a save whose landmass layer is out of step (STORY-017)" do
    test "the paint repairs the layer, says so, and leaves it consistent", %{
      conn: conn,
      save: save
    } do
      session_id = "paint-type-repair-#{System.unique_integer([:positive])}"
      conn = init_test_session(conn, %{"mirror_session_id" => session_id})
      view = editing(conn, save, "type")

      # The default fixture is forest with landmass all 1, including its ocean pocket
      # and the polar rows, which the rule says are 0.
      before = Mirror.SessionStore.get(session_id)
      terrain = %{arcanus: before.planes.arcanus.terrain, myrror: before.planes.myrror.terrain}
      landmass = %{arcanus: before.planes.arcanus.landmass, myrror: before.planes.myrror.landmass}
      assert Mirror.Landmass.violations(terrain, landmass) != []

      click(view, 30, 20)

      assert view |> element("#paint-report") |> render() |> text_of() =~ "1 tile changed"

      assert view |> element("#paint-report") |> render() |> text_of() =~
               "landmass layer repaired on"

      after_ = Mirror.SessionStore.get(session_id)
      terrain = %{arcanus: after_.planes.arcanus.terrain, myrror: after_.planes.myrror.terrain}
      landmass = %{arcanus: after_.planes.arcanus.landmass, myrror: after_.planes.myrror.landmass}

      # Arcanus now follows the rule; Myrror, the plane we did not paint on, is left
      # exactly as it was (it is out of step too, and that is not ours to touch)
      arcanus_problems =
        Enum.filter(Mirror.Landmass.violations(terrain, landmass), fn
          {:id_shared, _id, _owners} -> false
          violation -> elem(violation, 1) == :arcanus
        end)

      assert arcanus_problems == []
      assert after_.planes.myrror.landmass == before.planes.myrror.landmass

      # one undo puts everything back
      render_click(view, "undo", %{})
      assert Mirror.SessionStore.get(session_id).planes == before.planes
    end
  end

  describe "real-save integration" do
    @tag skip:
           !@has_real_save_and_sprites &&
             "needs MIRROR_MOM_PATH/(SAVE1.GAM, MAPBACK.LBX, UNITS1.LBX, UNITS2.LBX)"
    test "loading real SAVE1.GAM pushes Arcanus cities and sprites", %{conn: conn, dir: dir} do
      real_save = Path.join(dir, "REAL_SAVE1.GAM")
      File.cp!(@real_save_source, real_save)

      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => real_save}})

      assert_push_event(view, "overlay_data", %{layer: "cities", items: items})
      assert length(items) == 16
      assert %{x: 38, y: 21, frame: 0, banner: :yellow, name: "Deventor", walled: false} in items

      assert_push_event(view, "overlay_data", %{layer: "units", items: units})
      # All 42 starting units in SAVE1 are garrisons inside cities, so none appear on the field
      assert units == []

      assert_push_event(view, "overlay_data", %{layer: "roads", items: roads})
      # Arcanus has 35 roads + 35 specials
      assert length(roads) == 70
      assert Enum.any?(roads, &(&1.kind == :road))
      assert Enum.any?(roads, &(&1.kind == :special))

      assert_push_event(view, "overlay_sprites", %{
        cities: %{city: %{width: 32, height: 30}},
        roads: %{c: %{width: 20, height: 18}},
        enchanted_roads: %{c: %{width: 20, height: 18}},
        specials: %{gold: %{width: 20, height: 18}},
        corruption: %{corruption: %{width: 22, height: 18}},
        plaques: %{blue: %{width: 20, height: 18}},
        units: %{0 => %{width: 18, height: 16}}
      })
    end

    @tag skip:
           !@has_real_save_and_sprites &&
             "needs MIRROR_MOM_PATH/(SAVE1.GAM, MAPBACK.LBX, UNITS1.LBX, UNITS2.LBX)"
    test "a tab opened before any save gets the sprites on the first cross-tab load (STORY-044)",
         %{conn: conn, dir: dir} do
      real_save = Path.join(dir, "REAL_SAVE1.GAM")
      File.cp!(@real_save_source, real_save)

      session_id = "overlay-sprites-#{System.unique_integer([:positive])}"
      conn = init_test_session(conn, %{"mirror_session_id" => session_id})
      {:ok, tab1, _} = live(conn, ~p"/arcanus")
      {:ok, tab2, _} = live(conn, ~p"/arcanus")

      tab1 |> element("#load-form") |> render_submit(%{"load" => %{"path" => real_save}})

      assert_push_event(tab2, "overlay_sprites", %{cities: %{city: %{width: 32}}})
      assert_push_event(tab2, "overlay_data", %{layer: "cities", items: items})
      assert length(items) == 16
    end

    @tag skip:
           !@has_real_save_and_sprites &&
             "needs MIRROR_MOM_PATH/(SAVE1.GAM, MAPBACK.LBX, UNITS1.LBX, UNITS2.LBX)"
    test "the sprites are pushed once per socket, not again by later loads (STORY-044)",
         %{conn: conn, dir: dir} do
      real_save = Path.join(dir, "REAL_SAVE1.GAM")
      File.cp!(@real_save_source, real_save)

      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => real_save}})
      assert_push_event(view, "overlay_sprites", %{cities: %{city: %{width: 32}}})

      # Loading again re-sends the items, but not the sprite bank.
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => real_save}})
      assert_push_event(view, "overlay_data", %{layer: "cities", items: [_ | _]})
      refute_push_event(view, "overlay_sprites", _, 100)
    end

    @tag skip: !@has_real_save && "needs MIRROR_MOM_PATH/SAVE1.GAM"
    test "real SAVE1.GAM overwrite protection and Save as", %{conn: conn, dir: dir} do
      real_save = Path.join(dir, "REAL_SAVE1.GAM")
      File.cp!(@real_save_source, real_save)
      view = editing(conn, real_save)
      original = File.read!(real_save)
      click(view, 1, 1)

      html = view |> element("#save-form") |> render_submit(%{"save" => %{"path" => real_save}})
      assert html =~ "won&#39;t overwrite"
      assert File.read!(real_save) == original

      target = Path.join(dir, "SAVE2.GAM")
      view |> element("#save-form") |> render_submit(%{"save" => %{"path" => target}})
      assert File.exists?(target)
      assert byte_size(File.read!(target)) == byte_size(original)
      assert File.read!(target) != original
    end

    @tag skip: !@has_real_save && "needs MIRROR_MOM_PATH/SAVE1.GAM"
    test "real SAVE1.GAM surveyor matches known readouts at Deventor", %{conn: conn, dir: dir} do
      real_save = Path.join(dir, "REAL_SAVE1.GAM")
      File.cp!(@real_save_source, real_save)

      {:ok, view, _} = live(conn, ~p"/arcanus")
      view |> element("#load-form") |> render_submit(%{"load" => %{"path" => real_save}})

      pointer(view, "hover", 38, 21)
      card = view |> element("#surveyor") |> render() |> text_of()
      assert card =~ ~r/Hills\s*1\/2 food\s*\+3% production\s*Hamlet of\s*Deventor/
    end
  end

  @save_size 123_300
  @forest 0xA3
  @hills 0x113
  @mountain 0x10A
  @ocean 0x00

  defp synthetic_save_bytes do
    raw = :binary.copy(<<0>>, @save_size)

    # 1. Sites region filled with 0xFF so unused records are off-map (x=255)
    nodes_offset = 0x6058
    sites_end = 0x6628 + 102 * 24
    raw = put_bytes(raw, nodes_offset, :binary.copy(<<0xFF>>, sites_end - nodes_offset))

    # Known tower and magic node from SitesTest
    raw = put_bytes(raw, 0x6610, <<48, 28, 0xFF, 0>>)

    raw =
      put_bytes(raw, nodes_offset, <<42, 10, 0, 0, 5>> <> :binary.copy(<<0>>, 40) <> <<0, 2, 0>>)

    # 2. Wizard 0 banner = 4 (Yellow)
    raw = put_bytes(raw, 0x09E8 + 0x16, <<4>>)

    # 3. Cities: 16 cities so length matches real SAVE1.GAM, with Deventor at (38, 21)
    raw = put_bytes(raw, 0x09E0, <<16::little-16>>)

    deventor =
      String.pad_trailing("Deventor", 14, <<0>>) <>
        <<5, 38, 21, 0, 0, 1, 4>> <>
        :binary.copy(<<0>>, 10) <>
        :binary.copy(<<0xFF>>, 36) <>
        :binary.copy(<<0>>, 26) <>
        :binary.copy(<<0>>, 8) <>
        :binary.copy(<<0>>, 13)

    raw = put_bytes(raw, 0x8AAC, deventor)

    raw =
      Enum.reduce(1..15, raw, fn i, acc ->
        record =
          String.pad_trailing("City#{i}", 14, <<0>>) <>
            <<5, 10 + i * 2, 35, 0, 5, 1, 2>> <>
            :binary.copy(<<0>>, 10) <>
            :binary.copy(<<0xFF>>, 36) <>
            :binary.copy(<<0>>, 26) <>
            :binary.copy(<<0>>, 8) <>
            :binary.copy(<<0>>, 13)

        put_bytes(acc, 0x8AAC + i * 114, record)
      end)

    # 4. Terrain: 2400 tiles per plane.
    # Default forest, (1, 1)=10, (2, 1)=20, (38, 21)=hills, (39, 20)=mountain, (4..6, 4..6)=ocean
    arcanus_tiles =
      for y <- 0..39, x <- 0..59, into: <<>> do
        tile =
          cond do
            x == 1 and y == 1 -> 10
            x == 2 and y == 1 -> 20
            x == 38 and y == 21 -> @hills
            x == 39 and y == 20 -> @mountain
            x in 4..6 and y in 4..6 -> @ocean
            true -> @forest
          end

        <<tile::little-16>>
      end

    myrror_tiles = :binary.copy(<<@ocean::little-16>>, 2400)
    raw = put_bytes(raw, 0x002698, arcanus_tiles <> myrror_tiles)

    # 5. Landmass
    raw = put_bytes(raw, 0x004D98, :binary.copy(<<1>>, 4800))

    # 6. Minerals: 4 (Gold Ore) at (39, 20)
    minerals =
      for y <- 0..39, x <- 0..59, into: <<>> do
        val = if x == 39 and y == 20, do: 4, else: 0
        <<val>>
      end

    raw = put_bytes(raw, 0x013554, minerals <> :binary.copy(<<0>>, 2400))

    # 7. Exploration: 0 at (0, 0), 15 elsewhere
    exploration =
      for y <- 0..39, x <- 0..59, into: <<>> do
        val = if x == 0 and y == 0, do: 0, else: 15
        <<val>>
      end

    raw = put_bytes(raw, 0x014814, exploration <> :binary.copy(<<0>>, 2400))

    # 8. Terrain flags
    raw = put_bytes(raw, 0x01CBB8, :binary.copy(<<0>>, 4800))

    raw
  end

  defp put_bytes(raw, at, bytes) do
    size = byte_size(bytes)
    <<head::binary-size(^at), _::binary-size(^size), tail::binary>> = raw
    head <> bytes <> tail
  end

  defp put_byte(raw, at, byte) do
    put_bytes(raw, at, <<byte>>)
  end

  defp ray_observations(dataset_id) do
    Mirror.Stats.export(dataset_id).data
    |> Enum.filter(fn {k, _v} ->
      String.starts_with?(k, "ray:") or String.starts_with?(k, "ray_pair:")
    end)
    |> Map.new()
  end
end
