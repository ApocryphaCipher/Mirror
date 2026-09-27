defmodule Mirror.EditorTest do
  use ExUnit.Case, async: true

  alias Mirror.Editor
  alias Mirror.SaveFile

  defp make_test_state do
    arcanus_terrain = :binary.copy(<<0::little-16>>, 2400)
    myrror_terrain = :binary.copy(<<10::little-16>>, 2400)

    arcanus_flags = :binary.copy(<<0>>, 2400)
    myrror_flags = :binary.copy(<<0>>, 2400)

    raw_planes = %{
      arcanus: %{terrain: arcanus_terrain, terrain_flags: arcanus_flags},
      myrror: %{terrain: myrror_terrain, terrain_flags: myrror_flags}
    }

    planes = Editor.with_computed_layers(raw_planes)

    save = %SaveFile{
      path: "/fake/SAVE1.GAM",
      planes: raw_planes,
      raw: <<>>
    }

    %{
      save: save,
      planes: planes,
      original_planes: raw_planes,
      active_layer: :terrain,
      selection: %{terrain: 5, terrain_flags: 1},
      history: %{arcanus: [], myrror: []},
      redo: %{arcanus: [], myrror: []},
      dataset_id: nil
    }
  end

  describe "coordinate and layer validation" do
    test "valid_coord? bounds" do
      assert Editor.valid_coord?(0, 0)
      assert Editor.valid_coord?(59, 39)
      refute Editor.valid_coord?(-1, 0)
      refute Editor.valid_coord?(0, -1)
      refute Editor.valid_coord?(60, 0)
      refute Editor.valid_coord?(0, 40)
      refute Editor.valid_coord?("0", 0)
    end

    test "layer types" do
      assert Editor.u16_layer?(:terrain)
      refute Editor.u16_layer?(:terrain_flags)
      assert Editor.u8_layer?(:terrain_flags)
      assert Editor.u8_layer?(:computed_adj_mask)
    end

    test "clamp_value" do
      assert Editor.clamp_value(:terrain, -5) == 0
      assert Editor.clamp_value(:terrain, 761) == 761
      assert Editor.clamp_value(:terrain, 999) == 761

      assert Editor.clamp_value(:terrain_flags, -1) == 0
      assert Editor.clamp_value(:terrain_flags, 255) == 255
      assert Editor.clamp_value(:terrain_flags, 300) == 255
    end
  end

  describe "plane computations and tile reading" do
    test "with_computed_layers and strip_computed" do
      planes = %{
        arcanus: %{terrain: :binary.copy(<<0::little-16>>, 2400)},
        myrror: %{terrain: :binary.copy(<<0::little-16>>, 2400)}
      }

      computed = Editor.with_computed_layers(planes)
      assert Map.has_key?(computed.arcanus, :computed_adj_mask)
      assert byte_size(computed.arcanus.computed_adj_mask) == 2400

      stripped = Editor.strip_computed(computed)
      refute Map.has_key?(stripped.arcanus, :computed_adj_mask)
    end

    test "tile_value and original_tile_value" do
      state = make_test_state()
      assert Editor.tile_value(state, :arcanus, :terrain, 0, 0) == 0
      assert Editor.tile_value(state, :myrror, :terrain, 0, 0) == 10
      assert Editor.original_tile_value(state, :arcanus, :terrain, 0, 0) == 0
      assert Editor.tile_value(state, :arcanus, :terrain, -1, 0) == nil
    end

    test "changed_tile_count" do
      state = make_test_state()
      assert Editor.changed_tile_count(state) == 0

      {updated_state, _change, _updates} =
        Editor.apply_tile(state, :arcanus, :terrain, 5, 5, 42)

      assert Editor.changed_tile_count(updated_state) == 1
    end
  end

  describe "state transitions" do
    test "apply_tile rejects invalid coords and computed_adj_mask" do
      state = make_test_state()

      {same_state, change, updates} =
        Editor.apply_tile(state, :arcanus, :computed_adj_mask, 0, 0, 1)

      assert change == nil
      assert updates == []
      assert same_state == state

      {same_state, change, updates} = Editor.apply_tile(state, :arcanus, :terrain, -1, 0, 1)
      assert change == nil
      assert updates == []
      assert same_state == state
    end

    test "apply_tile updates plane, save, and computed_adj_mask for terrain" do
      state = make_test_state()

      {updated_state, change, updates} =
        Editor.apply_tile(state, :arcanus, :terrain, 10, 10, 20)

      assert change == {0, 20}
      assert updates == [%{x: 10, y: 10, value: 20}]
      assert Editor.tile_value(updated_state, :arcanus, :terrain, 10, 10) == 20
      assert Editor.original_tile_value(updated_state, :arcanus, :terrain, 10, 10) == 0
      refute Map.has_key?(updated_state.save.planes.arcanus, :computed_adj_mask)
    end

    test "start_stroke on matching tile creates empty stroke; drag records :new on first difference" do
      state = make_test_state()
      # Tile at (0, 0) is already 0. Starting a stroke with 0 creates empty stroke.
      {state, stroke, change, updates} =
        Editor.start_stroke(state, :arcanus, :terrain, 0, 0, 0)

      assert Map.take(stroke, [:layer, :changes]) == %{layer: :terrain, changes: %{}}
      assert is_integer(stroke[:id])
      assert change == nil
      assert updates == []
      assert state.history.arcanus == []

      # Drag to (1, 0) painting 5
      {state, stroke, change, updates} =
        Editor.apply_stroke_change(state, stroke, :arcanus, :terrain, 1, 0, 5)

      assert change == {0, 5}
      assert updates == [%{x: 1, y: 0, value: 5}]
      assert stroke.changes == %{{1, 0} => {0, 5}}
      assert length(state.history.arcanus) == 1
      assert hd(state.history.arcanus).changes == [{1, 0, 0, 5}]

      # Drag to (2, 0) painting 5 updates head of history (:update mode)
      {state, stroke, change, _updates} =
        Editor.apply_stroke_change(state, stroke, :arcanus, :terrain, 2, 0, 5)

      assert change == {0, 5}
      assert map_size(stroke.changes) == 2
      assert length(state.history.arcanus) == 1
      assert length(hd(state.history.arcanus).changes) == 2
    end

    test "undo and redo cycle edits correctly" do
      state = make_test_state()

      {state, stroke, _change, _updates} =
        Editor.start_stroke(state, :arcanus, :terrain, 5, 5, 25)

      {state, _stroke, _change, _updates} =
        Editor.apply_stroke_change(state, stroke, :arcanus, :terrain, 6, 5, 25)

      assert Editor.tile_value(state, :arcanus, :terrain, 5, 5) == 25
      assert Editor.tile_value(state, :arcanus, :terrain, 6, 5) == 25
      assert Editor.changed_tile_count(state) == 2
      assert length(state.history.arcanus) == 1
      assert state.redo.arcanus == []

      # Undo
      {undone_state, {:applied, updates, layer, changes}} = Editor.undo(state, :arcanus)
      assert layer == :terrain
      assert length(updates) == 2
      assert length(changes) == 2
      assert Editor.tile_value(undone_state, :arcanus, :terrain, 5, 5) == 0
      assert Editor.tile_value(undone_state, :arcanus, :terrain, 6, 5) == 0
      assert Editor.changed_tile_count(undone_state) == 0
      assert undone_state.history.arcanus == []
      assert length(undone_state.redo.arcanus) == 1

      # Redo
      {redone_state, {:applied, updates, layer, changes}} = Editor.redo(undone_state, :arcanus)
      assert layer == :terrain
      assert length(updates) == 2
      assert length(changes) == 2
      assert Editor.tile_value(redone_state, :arcanus, :terrain, 5, 5) == 25
      assert Editor.tile_value(redone_state, :arcanus, :terrain, 6, 5) == 25
      assert Editor.changed_tile_count(redone_state) == 2
      assert length(redone_state.history.arcanus) == 1
      assert redone_state.redo.arcanus == []
    end

    test "apply_single_tile records to history and clears redo" do
      state = make_test_state()

      {state, {:applied, stroke, updates}} =
        Editor.apply_single_tile(state, :arcanus, :terrain_flags, 3, 3, 7)

      assert Map.take(stroke, [:layer, :changes]) == %{
               layer: :terrain_flags,
               changes: [{3, 3, 0, 7}]
             }

      assert is_integer(stroke[:id])
      assert updates == [%{x: 3, y: 3, value: 7}]
      assert length(state.history.arcanus) == 1
      assert Editor.tile_value(state, :arcanus, :terrain_flags, 3, 3) == 7

      # Undo single tile
      {undone_state, {:applied, _updates, _layer, _changes}} = Editor.undo(state, :arcanus)
      assert Editor.tile_value(undone_state, :arcanus, :terrain_flags, 3, 3) == 0
    end

    test "concurrent stroke continuation preserves interleaved stroke from another tab (STORY-043)" do
      state = make_test_state()

      # Tab A starts a drag stroke on Arcanus at (1, 1)
      {state, stroke_a, _change, _updates} =
        Editor.start_stroke(state, :arcanus, :terrain, 1, 1, 10)

      # Tab A continues drag to (1, 2)
      {state, stroke_a, _change, _updates} =
        Editor.apply_stroke_change(state, stroke_a, :arcanus, :terrain, 1, 2, 10)

      # Tab B commits a separate single-tile stroke in between at (5, 5)
      {state, stroke_b, _change, _updates} =
        Editor.start_stroke(state, :arcanus, :terrain, 5, 5, 20)

      assert length(state.history.arcanus) == 2
      assert hd(state.history.arcanus).id == stroke_b.id

      # Tab A continues drag to (1, 3)
      {state, _stroke_a, _change, _updates} =
        Editor.apply_stroke_change(state, stroke_a, :arcanus, :terrain, 1, 3, 10)

      # Tab B's stroke must remain at the head of history and not be clobbered
      assert length(state.history.arcanus) == 2
      assert hd(state.history.arcanus).id == stroke_b.id

      # Undoing once removes only Tab B's tile (5, 5), leaving Tab A's drag intact
      {undone_b, _} = Editor.undo(state, :arcanus)
      assert Editor.tile_value(undone_b, :arcanus, :terrain, 5, 5) == 0
      assert Editor.tile_value(undone_b, :arcanus, :terrain, 1, 1) == 10
      assert Editor.tile_value(undone_b, :arcanus, :terrain, 1, 2) == 10
      assert Editor.tile_value(undone_b, :arcanus, :terrain, 1, 3) == 10

      # Undoing a second time removes Tab A's whole drag
      {undone_a, _} = Editor.undo(undone_b, :arcanus)
      assert Editor.tile_value(undone_a, :arcanus, :terrain, 1, 1) == 0
      assert Editor.tile_value(undone_a, :arcanus, :terrain, 1, 2) == 0
      assert Editor.tile_value(undone_a, :arcanus, :terrain, 1, 3) == 0
    end

    test "discard restores planes and clears history and redo" do
      state = make_test_state()

      {state, _stroke, _change, _updates} =
        Editor.start_stroke(state, :arcanus, :terrain, 1, 1, 99)

      assert Editor.changed_tile_count(state) == 1

      {discarded_state, restored_save} = Editor.discard(state)
      assert Editor.changed_tile_count(discarded_state) == 0
      assert Editor.tile_value(discarded_state, :arcanus, :terrain, 1, 1) == 0
      assert discarded_state.history == %{arcanus: [], myrror: []}
      assert discarded_state.redo == %{arcanus: [], myrror: []}
      assert restored_save.planes == state.original_planes
    end
  end
end
