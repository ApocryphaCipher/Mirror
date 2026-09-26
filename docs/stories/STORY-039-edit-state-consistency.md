# STORY-039: The editor's state gets out of step

**Parent:** [EPIC-008](../epics/EPIC-008-keeping-the-lights-on.md)
**Status:** **Done** (2026-09-26)
**Size:** medium

From the [review note](../notes/2026-09-24-ktlo-review.md). Each is a
separate small fix:

- **Discard doesn't refresh the settleable and fog overlays.** *Verified
  by Claude; it's Claude's own miss.* STORY-035's outcome says otherwise.
  `discard_edits` pushes the map but not `push_map_layers/1`.
- **After Save as, discard reloads the engine from the original file,**
  while the canvas shows the last-saved planes. Hover inspection then
  disagrees with the map.
- **Undo and redo skip the statistics update** (`apply_stroke/4` versus
  `do_apply_change/7`), so the research stats drift from the map.
- **A paint drag that starts on a tile already matching the brush
  paints nothing** (no active stroke is created).
- **Terrain edits don't push the recomputed adjacency masks,** so the
  Lab's adjacency overlay goes stale.
- **Two tabs on one session overwrite each other's edits** (whole-state
  writes to `SessionStore`).
- **Load and discard start engine sessions and never stop the old
  ones,** so memory grows.
- **The Lab is sent `edit_mode: "view"`,** which disables its painting
  and wheel controls on the client.

## Outcome

All 8 fixes implemented with unit and LiveView tests:
1. `discard_edits` now calls `refresh_hover/1` and `push_map_layers/1` to
   refresh settleable and fog overlays alongside the map.
2. `Session.load_save/2` now accepts `%SaveFile{}` directly, and discard
   rebuilds the engine from the restored in-memory planes; `save_file`
   updates `state.save` path and planes.
3. `apply_stroke/4` routes undo and redo operations through
   `update_stroke_stats/6`, keeping adjacency histogram counts and ray
   stats in sync.
4. `start_stroke/5` initializes an active stroke with empty changes when
   clicking a tile matching the brush; `apply_stroke_change/4` records
   history as `:new` when the first actual change occurs during drag.
5. `maybe_push_updates/4` emits `engine_delta` for `computed_adj_mask`
   alongside terrain changes so the client's adjacency overlay stays current.
6. `SessionStore` broadcasts updates via `Mirror.PubSub` and serializes
   updates through `GenServer.call/2`; connected map LiveViews subscribe on
   mount and synchronize state and canvas without overwriting drafts.
7. `SessionSupervisor.stop_session/1` and `Session.stop/1` terminate
   superseded engine sessions on `load_save`, `discard_edits`, and
   `ensure_engine_session`, and clean up failed start attempts.
8. `handle_edit_params/2` omits `edit_mode` event emission for Lab views
   (`lab?: true`), preserving the `"lab"` interaction mode.

## Done when

Each fix has a LiveView or unit test that fails without it.
