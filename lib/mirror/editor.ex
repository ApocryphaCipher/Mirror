defmodule Mirror.Editor do
  @moduledoc """
  Pure state transitions for the map editor.

  Handles tile modifications, stroke management, undo/redo history, discard,
  and research statistics synchronization. LiveViews and session processes delegate
  state mutations here so edit behavior stays consistent across user interactions.
  """

  alias Mirror.Map, as: MirrorMap
  alias Mirror.{Landmass, Stats, TerrainLbx, TerrainPaint}

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
  Applies one edit that changes several layers at once and records it as a
  **single undo step** (so undo and redo restore every layer together).

  `edits` is a list of `{layer, [{x, y, value}]}`, for example terrain tiles plus
  the landmass IDs that go with them. A layer listed more than once is merged
  (its edits in order), and if it lists the same tile more than once the last
  value wins, so a step has one part per layer and undo restores the original.
  The first layer that actually changes is the entry's main layer; the others
  ride along in its `:also` list.

  Returns `{state, :none}` when nothing changed, otherwise
  `{updated_state, {:applied, entry, layers}}` where `layers` is a list of
  `%{layer: layer, updates: [...], changes: [{x, y, prev, new}]}`, one per layer
  that changed, ready for the client and the engine.
  """
  def apply_compound(state, plane, edits) when is_list(edits) do
    {next_state, layers} =
      Enum.reduce(group_by_layer(edits), {state, []}, fn {layer, tile_edits},
                                                         {acc_state, acc_layers} ->
        tile_edits = last_value_per_tile(tile_edits)

        {st, changes, updates} =
          Enum.reduce(tile_edits, {acc_state, [], []}, fn {x, y, value}, {s, cs, us} ->
            case apply_tile(s, plane, layer, x, y, value) do
              {s2, {prev, new}, u} -> {s2, [{x, y, prev, new} | cs], u ++ us}
              {s2, nil, _} -> {s2, cs, us}
            end
          end)

        case changes do
          [] ->
            {st, acc_layers}

          _ ->
            part = %{layer: layer, updates: Enum.reverse(updates), changes: Enum.reverse(changes)}
            {st, acc_layers ++ [part]}
        end
      end)

    case layers do
      [] ->
        {state, :none}

      [main | rest] ->
        entry = %{
          id: System.unique_integer([:positive, :monotonic]),
          layer: main.layer,
          changes: main.changes,
          also: Enum.map(rest, &%{layer: &1.layer, changes: &1.changes})
        }

        history = [entry | Map.get(next_state.history, plane, [])]

        updated_state = %{
          next_state
          | history: Map.put(next_state.history, plane, history),
            redo: Map.put(next_state.redo, plane, [])
        }

        {updated_state, {:applied, entry, layers}}
    end
  end

  # A layer listed more than once is merged into its first entry (edits in order),
  # so a step has at most one part per layer and undo can restore it exactly.
  defp group_by_layer(edits) do
    {order, by_layer} =
      Enum.reduce(edits, {[], %{}}, fn {layer, tile_edits}, {order, by_layer} ->
        order = if Map.has_key?(by_layer, layer), do: order, else: [layer | order]
        {order, Map.update(by_layer, layer, tile_edits, &(&1 ++ tile_edits))}
      end)

    for layer <- Enum.reverse(order), do: {layer, Map.fetch!(by_layer, layer)}
  end

  # Several edits to one tile in a single step collapse to the last value, so the
  # recorded change is original -> final and undo restores the original.
  defp last_value_per_tile(tile_edits) do
    {order, values} =
      Enum.reduce(tile_edits, {[], %{}}, fn {x, y, value}, {order, values} ->
        order = if Map.has_key?(values, {x, y}), do: order, else: [{x, y} | order]
        {order, Map.put(values, {x, y}, value)}
      end)

    for {x, y} = key <- Enum.reverse(order), do: {x, y, Map.fetch!(values, key)}
  end

  @doc """
  Paints a terrain type (`:water`, `:grass`, ... see `Mirror.TerrainPaint.kinds/0`)
  onto `cells` of `plane`, re-tiling around them, and keeps the landmass layer
  consistent, all as one undo step.

  Returns `{state, outcome, report}`. `report` is `%{skipped, unresolved, stale}`
  from `Mirror.TerrainPaint.paint/3` (cells not painted or left unfixed), so the
  caller can warn. `outcome` is:

    * `:none`: nothing changed;
    * `{:applied, entry, layers}`: as for `apply_compound/3`;
    * `{:error, :out_of_ids}`: more landmasses than the layer can number; nothing
      was changed.

  The landmass IDs are recomputed for this plane only (`Mirror.Landmass.repair/3`
  with `only:`), never touching the other plane's layer. A state without landmass
  data (a fixture, say) just gets the terrain change.

  Pass `stroke: id` while a brush is being dragged: every call with the same id is
  folded into one undo step (the returned `layers` are still just this call's
  changes, for the client), so a drag can paint live and undo in one go.
  """
  def paint_type(state, plane, cells, kind, opts \\ []) do
    terrain = get_in(state, [:planes, plane, :terrain])
    result = TerrainPaint.paint(terrain, cells, kind)
    report = Map.take(result, [:skipped, :unresolved, :stale])

    if result.changes == [] do
      {state, :none, report}
    else
      terrain_edits = Enum.map(result.changes, fn {x, y, _prev, new} -> {x, y, new} end)

      case landmass_edits(state, plane, result.changes) do
        {:ok, landmass_edits} ->
          {next, outcome} =
            apply_compound(state, plane, [{:terrain, terrain_edits}, {:landmass, landmass_edits}])

          {next, outcome} = fold_into_stroke(next, plane, outcome, Keyword.get(opts, :stroke))
          {next, outcome, report}

        {:error, reason} ->
          {state, {:error, reason}, report}
      end
    end
  end

  # The step just recorded becomes part of stroke `id`: the first call takes the
  # id, later calls are composed into the entry that already has it.
  defp fold_into_stroke(state, _plane, outcome, nil), do: {state, outcome}
  defp fold_into_stroke(state, _plane, :none, _id), do: {state, :none}

  defp fold_into_stroke(state, plane, {:applied, entry, layers}, id) do
    [%{id: new_id} = new | rest] = Map.get(state.history, plane, [])
    true = new_id == entry.id

    # The stroke's earlier entry can be anywhere (another tab may have edited in
    # between), so it is updated in place by id, as record_stroke/4 does.
    case Enum.find_index(rest, &(Map.get(&1, :id) == id)) do
      nil ->
        renamed = %{new | id: id}
        {put_history(state, plane, [renamed | rest]), {:applied, renamed, layers}}

      index ->
        {before, [earlier | after_]} = Enum.split(rest, index)

        history =
          case compose_entries(earlier, new, id) do
            nil -> before ++ after_
            composed -> before ++ [composed | after_]
          end

        {put_history(state, plane, history), {:applied, entry, layers}}
    end
  end

  defp put_history(state, plane, history),
    do: %{state | history: Map.put(state.history, plane, history)}

  # Two entries for one stroke become one: per layer and tile, the earliest
  # previous value and the latest new value; tiles that end where they began drop
  # out. `nil` when nothing is left.
  defp compose_entries(earlier, later, id) do
    parts = fn entry ->
      [{entry.layer, entry.changes} | Enum.map(entry.also, &{&1.layer, &1.changes})]
    end

    order = Enum.uniq(Enum.map(parts.(earlier) ++ parts.(later), &elem(&1, 0)))

    composed =
      for layer <- order,
          changes =
            compose_changes(
              layer_changes(parts.(earlier), layer),
              layer_changes(parts.(later), layer)
            ),
          changes != [],
          do: {layer, changes}

    case composed do
      [] ->
        nil

      [{layer, changes} | rest] ->
        %{
          id: id,
          layer: layer,
          changes: changes,
          also: Enum.map(rest, fn {l, c} -> %{layer: l, changes: c} end)
        }
    end
  end

  defp layer_changes(parts, layer) do
    Enum.flat_map(parts, fn {l, changes} -> if l == layer, do: changes, else: [] end)
  end

  defp compose_changes(first, second) do
    {order, by_tile} =
      Enum.reduce(first ++ second, {[], %{}}, fn {x, y, prev, new}, {order, by_tile} ->
        case by_tile do
          %{{^x, ^y} => {first_prev, _}} -> {order, Map.put(by_tile, {x, y}, {first_prev, new})}
          _ -> {[{x, y} | order], Map.put(by_tile, {x, y}, {prev, new})}
        end
      end)

    for {x, y} = key <- Enum.reverse(order),
        {prev, new} = Map.fetch!(by_tile, key),
        prev != new,
        do: {x, y, prev, new}
  end

  # The landmass IDs that change for `plane` once the terrain changes are applied.
  defp landmass_edits(state, plane, terrain_changes) do
    planes = state.planes
    layers = Map.get(planes, plane, %{})

    if Enum.all?(Landmass.plane_keys(), fn p ->
         is_binary(get_in(planes, [p, :terrain])) and is_binary(get_in(planes, [p, :landmass]))
       end) do
      new_terrain =
        Enum.reduce(terrain_changes, layers.terrain, fn {x, y, _prev, new}, acc ->
          elem(MirrorMap.put_tile_u16_le(acc, x, y, new), 0)
        end)

      terrain = Map.new(Landmass.plane_keys(), &{&1, get_in(planes, [&1, :terrain])})
      terrain = Map.put(terrain, plane, new_terrain)
      landmass = Map.new(Landmass.plane_keys(), &{&1, get_in(planes, [&1, :landmass])})

      with {:ok, repaired} <- Landmass.repair(terrain, landmass, only: plane) do
        old = layers.landmass
        new = Map.fetch!(repaired, plane)

        edits =
          for y <- 0..(MirrorMap.height() - 1),
              x <- 0..(MirrorMap.width() - 1),
              value = MirrorMap.get_tile_u8(new, x, y),
              value != MirrorMap.get_tile_u8(old, x, y),
              do: {x, y, value}

        {:ok, edits}
      end
    else
      {:ok, []}
    end
  end

  @doc """
  Undoes the most recent stroke on `plane`.

  Returns `{state, {:applied, updates, layer, changes}}`, or
  `{state, {:applied, updates, layer, changes, extras}}` when the step also covered
  other layers (see `apply_compound/3`); `extras` is a list of
  `%{layer: layer, updates: [...], changes: [...]}`.
  """
  def undo(state, plane) do
    history = Map.get(state.history, plane, [])

    case history do
      [stroke | rest] ->
        {next_state, updates, layer, extras} = apply_stroke(state, plane, stroke, :undo)
        changes = stroke_changes(stroke, :undo)
        redo = [stroke | Map.get(next_state.redo, plane, [])]

        next_state = %{
          next_state
          | history: Map.put(next_state.history, plane, rest),
            redo: Map.put(next_state.redo, plane, redo)
        }

        {next_state, applied(updates, layer, changes, extras)}

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
        {next_state, updates, layer, extras} = apply_stroke(state, plane, stroke, :redo)
        changes = stroke_changes(stroke, :redo)
        history = [stroke | Map.get(next_state.history, plane, [])]

        next_state = %{
          next_state
          | history: Map.put(next_state.history, plane, history),
            redo: Map.put(next_state.redo, plane, rest)
        }

        {next_state, applied(updates, layer, changes, extras)}

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

  # One history entry: its main layer, then any further layers it covers.
  defp apply_stroke(state, plane, stroke, mode) do
    {state, updates, layer} = apply_stroke_layer(state, plane, stroke, mode)

    {state, extras} =
      Enum.reduce(Map.get(stroke, :also, []), {state, []}, fn part, {acc, extras} ->
        {acc, part_updates, part_layer} = apply_stroke_layer(acc, plane, part, mode)

        extra = %{
          layer: part_layer,
          updates: part_updates,
          changes: stroke_changes(part, mode)
        }

        {acc, [extra | extras]}
      end)

    {state, updates, layer, Enum.reverse(extras)}
  end

  defp applied(updates, layer, changes, []), do: {:applied, updates, layer, changes}
  defp applied(updates, layer, changes, extras), do: {:applied, updates, layer, changes, extras}

  defp apply_stroke_layer(state, plane, stroke, mode) do
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
