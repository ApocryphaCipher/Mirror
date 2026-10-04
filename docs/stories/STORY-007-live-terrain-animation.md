# STORY-007: Live terrain animation (ocean twinkle)

**Parent:** [EPIC-005](../epics/EPIC-005-animated-terrain-and-magic.md)
**Status:** open, ready to start (no dependency on STORY-006)
**Size:** small

## Findings so far (2026-10-04)

- The twinkling ocean is tile **601**, the only animated ocean tile (4
  frames); plain ocean is tile 0 (1 frame). The game places 601 at random,
  about 20% of ocean tiles in rows 2-37, and it never changes after map
  generation, so the animated cell list can be computed once per load.
  Evidence and numbers: `docs/reference/classic-terrain-format.md`.
- 42 plane-0 tiles are animated in all (37 on plane 1), and most are not
  ocean: shoreline-wave coast pieces (34-49, 146-161), a channel piece (54), the
  node tiles (168-170), the volcano (179) and the lake (18), plus three
  ocean sparkle pieces (31-33) beside 601. Table with the evidence in
  `docs/reference/classic-terrain-format.md`.
- So "redraw only animated cells" covers coast and nodes too, not just open
  ocean. Ocean-twinkle-only is a valid first cut (601 and 31-33).

## What to do

- Add an animation clock to `map_hooks.js` (`requestAnimationFrame`,
  throttled to the game's pace, roughly 4–8 fps, to be tuned by eye against
  the real game) that advances a frame counter.
- On each tick, redraw **only animated cells** (precompute the list of
  `(x, y)` whose `[index, frames]` has `frames > 1`), using
  `frame = tick % frames`. The per-frame draw path already exists
  (`drawTerrainLbxTile` reads `phaseIndex`).
- Pause the clock when the tab is hidden, and add a UI toggle
  ("Animate terrain").
- ~~List the animated tile numbers in [../reference/classic-terrain-format.md](../reference/classic-terrain-format.md)~~
  (listed and identified). Still open, both low priority because they already
  look right in the map viewer: confirm tile 18 (lake) in a real map (only
  seen as a sprite; 179 is confirmed as the volcano), and which coastline
  shapes get the wave pieces (146-161) rather than static coast.

## Definition of done

- Ocean visibly twinkles in `/arcanus` and `/myrror`; static tiles are not
  redrawn each tick.
- Toggling it off leaves frame 0, which is identical to today's render.
