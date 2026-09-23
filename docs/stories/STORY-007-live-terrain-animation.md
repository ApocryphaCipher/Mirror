# STORY-007: Live terrain animation (ocean twinkle)

**Parent:** [EPIC-005](../epics/EPIC-005-animated-terrain-and-magic.md)
**Status:** open, ready to start (no dependency on STORY-006)
**Size:** small

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
- List the animated tile numbers in [../reference/classic-terrain-format.md](../reference/classic-terrain-format.md)
  (are they only ocean/shore, or also volcanoes/nodes?).

## Definition of done

- Ocean visibly twinkles in `/arcanus` and `/myrror`; static tiles are not
  redrawn each tick.
- Toggling it off leaves frame 0, which is identical to today's render.
