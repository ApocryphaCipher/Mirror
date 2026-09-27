defmodule Mirror.Editor do
  @moduledoc """
  Pure state transitions for the map editor.

  Handles tile modifications, stroke management, undo/redo history, discard,
  and research statistics synchronization. LiveViews and session processes delegate
  state mutations here so edit behavior stays consistent across user interactions.
  """

  alias Mirror.Map, as: MirrorMap
  alias Mirror.{Stats, TerrainLbx}

  @layers [
    :terrain,
    :terrain_flags,
    :minerals,
    :exploration,
    :landmass,
    :computed_adj_mask
  ]

  @u16_layers [:terrain]
  @u8_layers @layers -- (@u16_layers -- [:computed_adj_mask])

  @doc "All map layer keys."
  def layers, do: @layers

  @doc "Layers stored as 16-bit little-endian words."
  def u16_layers, do: @u16_layers

  @doc "Layers stored as single bytes."
  def u8_layers, do: @u8_layers

  @doc "Returns true if the layer is stored as 16-bit words."
  def u16_layer?(layer), do: layer in @u16_layers

  @doc "Returns true if the layer is stored as 8-bit bytes."
  def u8_layer?(layer), do: layer in @u8_layers

  @doc "Checks whether an (x, y) coordinate is within valid map bounds."
  def valid_coord?(x, y) when is_integer(x) and is_integer(y) do
    x in 0..(MirrorMap.width() - 1) and y in 0..(MirrorMap.height() - 1)
  end

  def valid_coord?(_x, _y), do: false

  @doc "Clamps a tile value to the valid range for the given layer."
  def clamp_value(:terrain, value) when is_integer(value) do
    value |> max(0) |> min(TerrainLbx.tiles_per_plane() - 1)
  end

  def clamp_value(layer, value) when is_integer(value) do
    if u16_layer?(layer) do
      value |> max(0) |> min(65_535)
    else
      value |> max(0) |> min(255)
    end
  end

  def clamp_value(_layer, fallback), do: fallback

  @doc "Reads the current value of a tile on a plane and layer from editor state."
  def tile_value(state, plane, layer, x, y) do
    with true <- valid_coord?(x, y),
         planes when is_map(planes) <- Map.get(state, :planes),
         plane_layers when is_map(plane_layers) <- Map.get(planes, plane),
         binary when is_binary(binary) <- Map.get(plane_layers, layer) do
      if u16_layer?(layer) do
        MirrorMap.get_tile_u16_le(binary, x, y)
      else
        MirrorMap.get_tile_u8(binary, x, y)
      end
    else
      _ -> nil
    end
  end

  @doc "Reads the original (loaded or last-saved) value of a tile from editor state."
  def original_tile_value(state, plane, layer, x, y) do
    with true <- valid_coord?(x, y),
         planes when is_map(planes) <- Map.get(state, :original_planes),
         plane_layers when is_map(plane_layers) <- Map.get(planes, plane),
         binary when is_binary(binary) <- Map.get(plane_layers, layer) do
      if u16_layer?(layer) do
        MirrorMap.get_tile_u16_le(binary, x, y)
      else
        MirrorMap.get_tile_u8(binary, x, y)
      end
    else
      _ -> nil
    end
  end

  @doc "Computes derived layers (such as computed adjacency masks) for each plane."
  def with_computed_layers(planes) when is_map(planes) do
    Enum.into(planes, %{}, fn {plane_key, plane_layers} ->
      computed = MirrorMap.computed_adj_mask(plane_layers.terrain)
      {plane_key, Map.put(plane_layers, :computed_adj_mask, computed)}
    end)
  end

  def with_computed_layers(other), do: other

  @doc "Strips derived computed layers that are not saved to disk."
  def strip_computed(planes) when is_map(planes) do
    Enum.into(planes, %{}, fn {plane_key, plane_layers} ->
      {plane_key, Map.delete(plane_layers, :computed_adj_mask)}
    end)
  end

  def strip_computed(other), do: other

  @doc "Counts the total number of tiles that differ from the loaded or last-saved version."
  def changed_tile_count(%{save: nil}), do: 0

  def changed_tile_count(%{planes: planes, original_planes: originals})
      when is_map(planes) and is_map(originals) do
    for {plane, original_layers} <- originals, reduce: 0 do
      acc ->
        current_layers = Map.get(planes, plane, %{})

        changed =
          for {layer, original} <- original_layers,
              current = Map.get(current_layers, layer),
              is_binary(current) and is_binary(original),
              current != original,
              width = if(u16_layer?(layer), do: 2, else: 1),
              idx <- 0..(div(byte_size(original), width) - 1),
              binary_part(original, idx * width, width) !=
                binary_part(current, idx * width, width),
              into: MapSet.new(),
              do: idx

        acc + MapSet.size(changed)
    end
  end

  def changed_tile_count(_state), do: 0

  @doc """
  Applies a single tile change to the editor state without recording stroke history.

  Returns `{updated_state, change, updates}` where `change` is `{prev_value, new_value}` or `nil`.
  """
  def apply_tile(state, plane, layer, x, y, value) do
    cond do
      layer == :computed_adj_mask ->
        {state, nil, []}

      not valid_coord?(x, y) ->
        {state, nil, []}

      true ->
        do_apply_change(state, plane, layer, x, y, value)
    end
  end

  @doc """
  Starts an interactive stroke at (x, y).

  Applies the tile change and initializes an active stroke. If the starting tile
  already matches `value`, an empty active stroke is returned so subsequent dragging
  can still paint tiles (STORY-039). If changed, history is updated with mode `:new`.

  Returns `{updated_state, active_stroke, change, updates}`.
  """
  def start_stroke(state, plane, layer, x, y, value) do
    {next_state, change, updates} = apply_tile(state, plane, layer, x, y, value)
    stroke_id = System.unique_integer([:positive, :monotonic])

    case change do
      nil ->
        stroke = %{
          id: stroke_id,
          layer: layer,
          changes: %{}
        }

        {next_state, stroke, nil, []}

      {prev, new} ->
        stroke = %{
          id: stroke_id,
          layer: layer,
          changes: %{{x, y} => {prev, new}}
        }

        updated_state = record_stroke(next_state, plane, stroke, :new)
        {updated_state, stroke, change, updates}
    end
  end

  @doc """
  Applies a drag step to an in-progress active stroke.

  If this drag step introduces the first change in an initially empty stroke,
  history records it as `:new`; otherwise it updates the head history entry (STORY-039).

  Returns `{updated_state, updated_active_stroke, change, updates}`.
  """
  def apply_stroke_change(state, stroke, plane, layer, x, y, value) do
    {next_state, change, updates} = apply_tile(state, plane, layer, x, y, value)

    case change do
      nil ->
        {next_state, stroke, nil, []}

      {prev, new} ->
        mode = if stroke.changes == %{}, do: :new, else: :update

        changes =
          Map.update(stroke.changes, {x, y}, {prev, new}, fn {old_prev, _old_new} ->
            {old_prev, new}
          end)

        updated_stroke = %{stroke | changes: changes}
        updated_state = record_stroke(next_state, plane, updated_stroke, mode)
        {updated_state, updated_stroke, change, updates}
    end
  end

  @doc """
  Applies a single tile modification and commits it directly to undo history.
  Used by inspector tools (bit toggles, invert, restore).
  """
  def apply_single_tile(state, plane, layer, x, y, value) do
    {next_state, change, updates} = apply_tile(state, plane, layer, x, y, value)

    case change do
      nil ->
        {state, :none}

      {prev, new} ->
        stroke = %{
          id: System.unique_integer([:positive, :monotonic]),
          layer: layer,
          changes: [{x, y, prev, new}]
        }

        history = [stroke | Map.get(next_state.history, plane, [])]
        redo = Map.put(next_state.redo, plane, [])

        updated_state = %{
          next_state
          | history: Map.put(next_state.history, plane, history),
            redo: redo
        }

        {updated_state, {:applied, stroke, updates}}
    end
  end

  @doc """
  Undoes the most recent stroke on `plane`.
  """
  def undo(state, plane) do
    history = Map.get(state.history, plane, [])

    case history do
      [stroke | rest] ->
        {next_state, updates, layer} = apply_stroke(state, plane, stroke, :undo)
        changes = stroke_changes(stroke, :undo)
        redo = [stroke | Map.get(next_state.redo, plane, [])]

        next_state = %{
          next_state
          | history: Map.put(next_state.history, plane, rest),
            redo: Map.put(next_state.redo, plane, redo)
        }

        {next_state, {:applied, updates, layer, changes}}

      [] ->
        {state, :none}
    end
  end

  @doc """
  Redoes the most recently undone stroke on `plane`.
  """
  def redo(state, plane) do
    redo = Map.get(state.redo, plane, [])

    case redo do
      [stroke | rest] ->
        {next_state, updates, layer} = apply_stroke(state, plane, stroke, :redo)
        changes = stroke_changes(stroke, :redo)
        history = [stroke | Map.get(next_state.history, plane, [])]

        next_state = %{
          next_state
          | history: Map.put(next_state.history, plane, history),
            redo: Map.put(next_state.redo, plane, rest)
        }

        {next_state, {:applied, updates, layer, changes}}

      [] ->
        {state, :none}
    end
  end

  @doc """
  Discards all in-memory edits, restoring the planes from original/last-saved planes
  and clearing history and redo queues.

  Returns `{updated_state, restored_save}` where `restored_save` is a `%SaveFile{}`
  ready to re-sync the engine session.
  """
  def discard(state) do
    updated_planes = with_computed_layers(state.original_planes)

    updated_state = %{
      state
      | planes: updated_planes,
        history: %{arcanus: [], myrror: []},
        redo: %{arcanus: [], myrror: []}
    }

    restored_save =
      if state.save do
        %{state.save | planes: state.original_planes}
      else
        nil
      end

    {updated_state, restored_save}
  end

  # --- Internal Helpers ---

  defp do_apply_change(state, plane, layer, x, y, value) do
    old_plane = Map.fetch!(state.planes, plane)

    {new_plane, prev_value} =
      if u16_layer?(layer) do
        {updated, prev} = MirrorMap.put_tile_u16_le(old_plane[layer], x, y, value)
        {Map.put(old_plane, layer, updated), prev}
      else
        {updated, prev} = MirrorMap.put_tile_u8(old_plane[layer], x, y, value)
        {Map.put(old_plane, layer, updated), prev}
      end

    if prev_value == value do
      {state, nil, []}
    else
      new_plane = maybe_update_adj_mask(new_plane, x, y, layer)
      new_planes = Map.put(state.planes, plane, new_plane)
      save = if state.save, do: %{state.save | planes: strip_computed(new_planes)}, else: nil
      updated_state = %{state | planes: new_planes, save: save}

      update_stats(updated_state, plane, layer, x, y, prev_value, value, old_plane, new_plane)

      updates = [%{x: x, y: y, value: value}]
      {updated_state, {prev_value, value}, updates}
    end
  end

  defp record_stroke(state, plane, stroke, mode) do
    stroke_id = Map.get(stroke, :id) || System.unique_integer([:positive, :monotonic])
    entry = %{id: stroke_id, layer: stroke.layer, changes: stroke_change_list(stroke)}
    plane_history = Map.get(state.history, plane, [])

    history =
      case mode do
        :update ->
          if Enum.any?(plane_history, &(Map.get(&1, :id) == stroke_id)) do
            Enum.map(plane_history, fn
              %{id: ^stroke_id} -> entry
              other -> other
            end)
          else
            [entry | plane_history]
          end

        _ ->
          [entry | plane_history]
      end

    %{
      state
      | history: Map.put(state.history, plane, history),
        redo: Map.put(state.redo, plane, [])
    }
  end

  defp stroke_change_list(%{changes: changes}) when is_map(changes) do
    Enum.map(changes, fn {{x, y}, {prev, new}} -> {x, y, prev, new} end)
  end

  defp stroke_change_list(%{changes: changes}) when is_list(changes) do
    changes
  end

  defp apply_stroke(state, plane, stroke, mode) do
    layer = stroke.layer
    plane_layers = Map.fetch!(state.planes, plane)

    {updated_layer, updates} =
      Enum.reduce(stroke.changes, {plane_layers[layer], []}, fn {x, y, prev, new},
                                                                {acc, updates} ->
        value = if mode == :undo, do: prev, else: new

        {updated, _old} =
          if u16_layer?(layer) do
            MirrorMap.put_tile_u16_le(acc, x, y, value)
          else
            MirrorMap.put_tile_u8(acc, x, y, value)
          end

        {updated, [%{x: x, y: y, value: value} | updates]}
      end)

    new_plane = Map.put(plane_layers, layer, updated_layer)
    new_plane = maybe_update_adj_mask_batch(new_plane, stroke, layer)
    new_planes = Map.put(state.planes, plane, new_plane)
    save = if state.save, do: %{state.save | planes: strip_computed(new_planes)}, else: nil
    updated_state = %{state | planes: new_planes, save: save}

    update_stroke_stats(updated_state, plane, stroke, mode, plane_layers, new_plane)

    {updated_state, updates, layer}
  end

  defp stroke_changes(stroke, :undo) do
    Enum.map(stroke.changes, fn {x, y, prev, new} -> {x, y, new, prev} end)
  end

  defp stroke_changes(stroke, :redo), do: stroke.changes

  defp update_stroke_stats(state, plane, stroke, mode, old_plane, new_plane) do
    if dataset_id = Map.get(state, :dataset_id) do
      layer = stroke.layer

      case layer do
        :terrain ->
          adj_coords =
            stroke.changes
            |> Enum.flat_map(fn {x, y, _prev, _new} -> MirrorMap.adj_update_coords(x, y) end)
            |> Enum.uniq()

          Enum.each(adj_coords, fn {cx, cy} ->
            old = MirrorMap.get_tile_u8(old_plane.computed_adj_mask, cx, cy)
            new = MirrorMap.get_tile_u8(new_plane.computed_adj_mask, cx, cy)

            if old != new do
              Stats.bump_hist(dataset_id, :computed_adj_mask, :global, old, -1)
              Stats.bump_hist(dataset_id, :computed_adj_mask, :global, new, 1)
            end
          end)

          ray_coords =
            stroke.changes
            |> Enum.flat_map(fn {x, y, _prev, _new} -> ray_update_coords(x, y) end)
            |> Enum.uniq()

          Enum.each(ray_coords, fn {cx, cy} ->
            Mirror.Map.Rays.observe_tile(dataset_id, old_plane.terrain, cx, cy, -1)
            Mirror.Map.Rays.observe_tile(dataset_id, new_plane.terrain, cx, cy, 1)
          end)

        _ ->
          Enum.each(stroke.changes, fn {x, y, prev, new} ->
            {prev_value, new_value} = if mode == :undo, do: {new, prev}, else: {prev, new}
            update_stats(state, plane, layer, x, y, prev_value, new_value, old_plane, new_plane)
          end)
      end
    end
  end

  defp update_stats(state, plane, layer, x, y, prev_value, new_value, old_plane, new_plane) do
    if dataset_id = Map.get(state, :dataset_id) do
      case layer do
        :terrain ->
          update_adjacent_stats(state, old_plane, new_plane, x, y)
          update_ray_stats(state, old_plane, new_plane, x, y)

        _ ->
          terrain_type =
            MirrorMap.terrain_type(MirrorMap.get_tile_u16_le(new_plane.terrain, x, y))

          Stats.bump_hist(dataset_id, layer, :global, prev_value, -1)
          Stats.bump_hist(dataset_id, layer, :global, new_value, 1)
          Stats.bump_hist(dataset_id, layer, {:plane, plane}, prev_value, -1)
          Stats.bump_hist(dataset_id, layer, {:plane, plane}, new_value, 1)
          Stats.bump_hist(dataset_id, layer, {:terrain_type, terrain_type}, prev_value, -1)
          Stats.bump_hist(dataset_id, layer, {:terrain_type, terrain_type}, new_value, 1)
      end
    end
  end

  defp update_adjacent_stats(state, old_plane, new_plane, x, y) do
    if dataset_id = Map.get(state, :dataset_id) do
      coords = MirrorMap.adj_update_coords(x, y)

      Enum.each(coords, fn {cx, cy} ->
        old = MirrorMap.get_tile_u8(old_plane.computed_adj_mask, cx, cy)
        new = MirrorMap.get_tile_u8(new_plane.computed_adj_mask, cx, cy)

        if old != new do
          Stats.bump_hist(dataset_id, :computed_adj_mask, :global, old, -1)
          Stats.bump_hist(dataset_id, :computed_adj_mask, :global, new, 1)
        end
      end)
    end
  end

  defp update_ray_stats(state, old_plane, new_plane, x, y) do
    if dataset_id = Map.get(state, :dataset_id) do
      coords = ray_update_coords(x, y)

      Enum.each(coords, fn {cx, cy} ->
        Mirror.Map.Rays.observe_tile(dataset_id, old_plane.terrain, cx, cy, -1)
        Mirror.Map.Rays.observe_tile(dataset_id, new_plane.terrain, cx, cy, 1)
      end)
    end
  end

  defp ray_update_coords(x, y) do
    for dy <- -2..2, dx <- -2..2 do
      nx = MirrorMap.wrap_x(x + dx)
      ny = MirrorMap.clamp_y(y + dy)
      {nx, ny}
    end
    |> Enum.reject(fn {_nx, ny} -> ny == :off end)
    |> Enum.uniq()
  end

  defp maybe_update_adj_mask(plane_layers, x, y, layer) do
    if layer == :terrain do
      coords = MirrorMap.adj_update_coords(x, y)

      updated =
        Enum.reduce(coords, plane_layers.computed_adj_mask, fn {cx, cy}, acc ->
          value = MirrorMap.adj_mask(plane_layers.terrain, cx, cy)
          {updated_bin, _old} = MirrorMap.put_tile_u8(acc, cx, cy, value)
          updated_bin
        end)

      Map.put(plane_layers, :computed_adj_mask, updated)
    else
      plane_layers
    end
  end

  defp maybe_update_adj_mask_batch(plane_layers, stroke, layer) do
    if layer == :terrain do
      coords =
        stroke.changes
        |> Enum.flat_map(fn {x, y, _prev, _new} -> MirrorMap.adj_update_coords(x, y) end)
        |> Enum.uniq()

      updated =
        Enum.reduce(coords, plane_layers.computed_adj_mask, fn {cx, cy}, acc ->
          value = MirrorMap.adj_mask(plane_layers.terrain, cx, cy)
          {updated_bin, _old} = MirrorMap.put_tile_u8(acc, cx, cy, value)
          updated_bin
        end)

      Map.put(plane_layers, :computed_adj_mask, updated)
    else
      plane_layers
    end
  end
end
