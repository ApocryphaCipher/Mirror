# STORY-014: Triage the UI; move research tools to a Lab route

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** done 2026-09-22. `/lab/:plane` holds all research tools (same
`MapLive`, `:lab` action). The map pages show the map with a slim header,
are hover-only (no painting), and always render terrain art with no
research overlays. The MOMIME path is removed (see backlog).
**Size:** small–medium

## What to do

Use the inventory table in [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md):

1. **Delete** the Kinds / Coast Audit / Shore Semantics toggles and their
   draw code. They only debug the retired MOMIME smoothing path. Pair this
   with the MOMIME-path removal (backlog) if that hasn't landed yet.
2. **Create `/lab/:plane`** (or `/lab` with a plane switch) and move there:
   Value intel + histogram, Bit flag lab, render-mode toggle, snapshot /
   phase / Detect Loop, Reload Tiles, Export Snapshot / Export Stats, and
   the raw-value painter (the current "paint any layer with a number"
   editor stays useful for format research). Link it from the header next
   to `/tile-probe`.
3. `/arcanus` / `/myrror` keep only what View and Edit need (STORY-015/016).

## Definition of done

- The map pages show no research controls; `/lab` has all of them working
  as before.
- No feature is lost: every control in the inventory is kept (in View,
  Edit or Lab) or deliberately deleted.
