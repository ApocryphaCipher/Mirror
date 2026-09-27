# STORY-043: Maintainability: map_live.ex and dead code

**Parent:** [EPIC-008](../epics/EPIC-008-keeping-the-lights-on.md)
**Status:** Done (2026-09-26)
**Size:** medium to large (do it after STORY-039 and STORY-041)

- `lib/mirror_web/live/map_live.ex` is about 3,400 lines. It mixes
  rendering, edit history, file I/O, stats and engine sync, and edits,
  undo/redo and discard each keep the same state their own way. That's
  where STORY-039's bugs come from. Pull the editor-state transitions and
  save orchestration into focused, tested modules. Do it only once
  STORY-041 gives CI coverage, so the refactor is checked.
- `Mirror.TileCache` has no callers. Propose deleting it as its own
  decision (AGENTS.md §3), or document why it stays.

## Done when

Edit, undo, redo and discard go through one state-transition path, and
`map_live.ex` is mostly rendering.

## Outcome

1. **Dead code removal:** Confirmed `Mirror.TileCache` had zero callers across the codebase, tests, and scripts. Removed `lib/mirror/tile_cache.ex` in a dedicated commit (`d05db11`) along with its unused configuration surface (`Mirror.Paths.tile_cache_dir/0`, `:tile_cache_dir`, and `MIRROR_TILE_CACHE`).
2. **Editor state transitions (`Mirror.Editor`):** Extracted state machine transitions (`apply_tile`, `start_stroke`, `apply_stroke_change`, `apply_single_tile`, `undo`, `redo`, `discard`, `tile_value`, `original_tile_value`, `changed_tile_count`, `with_computed_layers`, `strip_computed`, and layer stat tracking) into `Mirror.Editor` (`lib/mirror/editor.ex`). Tested thoroughly in `test/mirror/editor_test.exs` (13 unit tests).
3. **Save orchestration (`Mirror.SaveManager`):** Extracted save loading, writing with universal overwrite protection, engine session lifecycle (`ensure_engine_session`, `restore_engine_session`, `start_engine_session`, `stop_engine_session`), path normalization, and state normalization into `Mirror.SaveManager` (`lib/mirror/save_manager.ex`). Tested in `test/mirror/save_manager_test.exs` (17 unit tests).
4. **LiveView streamlined:** `lib/mirror_web/live/map_live.ex` delegates state transitions and save operations to `Mirror.Editor` and `Mirror.SaveManager`, reducing line count from ~3,600 to ~2,910 lines focused on event routing and rendering.
5. **Multi-tab session sync and concurrent strokes:** Fixed multi-tab sync in `handle_info({:session_state_updated, ...})`, save orchestration in `handle_event("save_file", ...)`, and stroke history tracking in `Mirror.Editor` so concurrent strokes identify entries by unique ID and never clobber interleaved strokes from other tabs.
6. All tests pass: 163 tests pass in CI mode (with 6 skipped game-file tests), and 169 pass when running with full game files via `scripts/test_game.sh`.
