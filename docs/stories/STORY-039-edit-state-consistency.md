# STORY-039: The editor's state gets out of step

**Parent:** [EPIC-008](../epics/EPIC-008-keeping-the-lights-on.md)
**Status:** open, P2
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

## Done when

Each fix has a LiveView or unit test that fails without it.
