# STORY-023 (bug): Painting in edit mode doesn't redraw the tile

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** open. For later; edits are saved correctly, only the live
display is wrong.
**Size:** small
**Reported by:** Kevin, 2026-09-23

## Symptom

In edit mode (`/arcanus?edit=terrain`), clicking a tile increments
"N tiles changed", but the map doesn't change on screen. The new tile only
appears after a page reload.

## What's confirmed (reproduced 2026-09-23 on `/myrror?edit=terrain`)

- Painted tile (52, 6) with brush 148: the counter went 16 → 17, but the
  canvas pixel at that tile was identical before and after
  (`8,4,4` → `8,4,4`).
- After a **reload**, the same pixel showed the new tile (`16,16,93`). So
  the **server session holds the edit**; only the **live redraw** is missing.
- Undo still works (count back to 16).

## Where to look

The live path is server `apply_tile_change` → `maybe_push_updates` →
`"engine_delta"` push → client `applyTileValue` → `drawStackedTile`.
Suspects, in order:

1. **`maybe_push_updates` guard**: it only pushes when
   `layer == socket.assigns.active_layer`. Edit mode forces `:terrain` for
   strokes (`tool_and_layer/3`), but `assigns.active_layer` comes from the
   session and may still be whatever the Lab last used. `handle_params`
   tries to set it, but only via `assign_from_state` when it differs, so
   check the ordering and whether it persists.
2. **`updates` empty**: check what `do_apply_change/6` returns for terrain
   (e.g. an engine-session path that yields no `updates`).
3. **Client**: confirm `engine_delta` arrives (`liveSocket.enableDebug()`),
   and that `applyTileValue` reaches `drawStackedTile` in view/edit
   (`renderMode === "tiles"`, atlas loaded).

## Also clarify the intended click behaviour

Kevin: "when I click a tile… I expect to view the next tile." Today a click
**stamps the brush tile**. That should show immediately (this bug). If the
intent is MMS-style "click cycles to the next picture of this tile",
that's a distinct tool: add a **Cycle** tool (left = next variant, right =
previous) next to **Stamp**. The best version belongs with STORY-017, which
knows which tiles are variants of the same terrain type.

## Definition of done

- In edit mode, a painted tile (and each tile of a drag) updates on screen
  immediately; so do Undo, Redo and Discard.
- `map_live_edit_test.exs` asserts the push: `assert_push_event(view,
  "engine_delta", %{changes: [%{x: 1, y: 1, new: 5}]})` after a paint. The
  current tests only check the counter, which is why this slipped through.
