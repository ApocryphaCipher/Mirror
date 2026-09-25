# STORY-043: Maintainability: map_live.ex and dead code

**Parent:** [EPIC-008](../epics/EPIC-008-keeping-the-lights-on.md)
**Status:** open, P3
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
