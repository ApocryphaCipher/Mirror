defmodule Mirror.SaveManagerTest do
  use ExUnit.Case, async: false

  alias Mirror.{Editor, SaveFile, SaveManager}

  describe "state normalization" do
    test "normalize_state initializes default editor state" do
      state = SaveManager.normalize_state(nil)
      assert state.save == nil
      assert state.planes == %{}
      assert state.active_layer == :terrain
      assert state.history == %{arcanus: [], myrror: []}
      assert state.redo == %{arcanus: [], myrror: []}
      assert is_map(state.selection)
      assert is_map(state.layer_visibility)
      assert is_map(state.layer_opacity)
    end
  end

  describe "layer helpers" do
    test "default_selection maps all layers to 0" do
      selection = SaveManager.default_selection()
      assert selection[:terrain] == 0
      assert selection[:terrain_flags] == 0
      assert selection[:minerals] == 0
    end

    test "default_layer_visibility makes terrain and active layer visible" do
      vis = SaveManager.default_layer_visibility(:minerals)
      assert vis[:terrain] == true
      assert vis[:minerals] == true
      assert vis[:exploration] == false
    end

    test "ensure_layer_visible ensures both terrain and specified layer are true" do
      state = %{active_layer: :terrain, layer_visibility: %{terrain: true, minerals: false}}
      updated = SaveManager.ensure_layer_visible(state, :minerals)
      assert updated.layer_visibility[:terrain] == true
      assert updated.layer_visibility[:minerals] == true
    end

    test "normalize_phase_loop_status" do
      assert SaveManager.normalize_phase_loop_status(:detected) == :detected
      assert SaveManager.normalize_phase_loop_status("detected") == :detected
      assert SaveManager.normalize_phase_loop_status(:assumed) == :assumed
      assert SaveManager.normalize_phase_loop_status("assumed") == :assumed
      assert SaveManager.normalize_phase_loop_status(:other) == :unknown
    end
  end

  describe "engine session lifecycle" do
    test "engine_session_alive? returns false for nil" do
      refute SaveManager.engine_session_alive?(nil)
    end

    test "stop_engine_session returns :ok for nil" do
      assert SaveManager.stop_engine_session(nil) == :ok
    end

    test "restore_engine_session leaves state unchanged if not given a SaveFile" do
      state = %{engine_session_id: nil}
      assert SaveManager.restore_engine_session(state, nil) == state
    end
  end

  describe "saves that arrive as bytes (EPIC-012)" do
    alias Mirror.{SaveFile, WizardFixture}

    test "load_bytes builds the same kind of state as loading a file, labelled with the name" do
      raw = WizardFixture.synthetic()
      assert {:ok, state, "SAVE3.GAM"} = SaveManager.load_bytes(raw, "SAVE3.GAM")
      assert state.save.raw == raw
      assert state.save_path == "SAVE3.GAM"
      assert state.original_raw == raw
      assert SaveManager.unsaved_count(state) == 0
      SaveManager.stop_engine_session(state.engine_session_id)
    end

    test "a loaded save has the computed layers and both planes" do
      assert {:ok, state, "SAVE1.GAM"} =
               SaveManager.load_bytes(WizardFixture.synthetic(), "SAVE1.GAM")

      assert state.active_layer == :terrain
      assert is_map(state.planes.arcanus) and is_map(state.planes.myrror)
      assert Map.has_key?(state.planes.arcanus, :computed_adj_mask)
      SaveManager.stop_engine_session(state.engine_session_id)
    end

    test "a tile edit goes into the bytes to write, and marking it saved clears the count" do
      {:ok, state, _} = SaveManager.load_bytes(WizardFixture.synthetic(), "SAVE1.GAM")
      {edited, _change, _updates} = Editor.apply_tile(state, :arcanus, :terrain, 0, 0, 99)
      assert Editor.changed_tile_count(edited) == 1

      {:ok, bytes} = SaveManager.slot_bytes(edited)
      assert bytes != WizardFixture.synthetic()
      assert byte_size(bytes) == byte_size(WizardFixture.synthetic())

      saved = SaveManager.mark_saved(edited, "SAVE2.GAM", bytes)
      assert Editor.changed_tile_count(saved) == 0
      assert saved.save_path == "SAVE2.GAM"
      SaveManager.stop_engine_session(state.engine_session_id)
    end

    test "bad bytes are an error, not a crash" do
      assert {:error, _} = SaveManager.load_bytes("not a save", "SAVE1.GAM")
      assert {:error, _} = SaveManager.load_bytes(<<>>, "SAVE1.GAM")
    end

    test "slot_bytes without a save, and mark_saved on a state without one" do
      assert SaveManager.slot_bytes(%{save: nil, planes: %{}}) == {:error, :no_save}
      assert SaveManager.mark_saved(%{save: nil}, "SAVE1.GAM", <<>>) == %{save: nil}
    end

    test "mark_saved clears the unsaved count only for exactly the bytes that were written" do
      {:ok, state, _} = SaveManager.load_bytes(WizardFixture.synthetic(), "SAVE1.GAM")

      edited = %{
        state
        | save: %{state.save | raw: WizardFixture.field(state.save.raw, 0, 0x24, <<99, 0>>)}
      }

      assert SaveManager.unsaved_count(edited) > 0

      {:ok, bytes} = SaveManager.slot_bytes(edited)
      saved = SaveManager.mark_saved(edited, "SAVE4.GAM", bytes)
      assert SaveManager.unsaved_count(saved) == 0
      assert saved.save_path == "SAVE4.GAM"
      assert %SaveFile{path: "SAVE4.GAM", raw: ^bytes} = saved.save

      # something else changed after those bytes were made: still unsaved
      later = %{
        edited
        | save: %{edited.save | raw: WizardFixture.field(edited.save.raw, 0, 0x24, <<7, 0>>)}
      }

      assert SaveManager.mark_saved(later, "SAVE4.GAM", bytes) == later
      SaveManager.stop_engine_session(state.engine_session_id)
    end
  end
end
