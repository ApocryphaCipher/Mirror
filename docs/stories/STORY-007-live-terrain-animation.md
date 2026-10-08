# STORY-007: Live terrain animation (ocean twinkle)

**Parent:** [EPIC-005](../epics/EPIC-005-animated-terrain-and-magic.md)
**Status:** Done (2026-10-07). Pace corrected the same day from a measurement of the real
game (see "The pace"), and Kevin confirmed it animating in his browser.
**Size:** small

## Findings so far (2026-10-04)

- The twinkling ocean is tile **601**, the only animated ocean tile (4
  frames); plain ocean is tile 0 (1 frame). The game places 601 at random,
  about 20% of ocean tiles in rows 2-37. In the game it never changes after
  map generation (checked 2026-10-04: the whole terrain block was
  byte-identical between turn 1 and five turns later in three worlds), so a
  load-time list is enough for a viewed save. **Mirror's editor changes
  tiles without reloading** (`assets/js/map_hooks.js`), so the animated-cell
  list must also be updated after any edit, including undo and redo (e.g.
  painting 0 → 601 adds a cell). Evidence and numbers:
  `docs/reference/classic-terrain-format.md`.
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
- Keep the animated-cell list in step with edits (paint, cycle, undo, redo),
  not only with the initial load.
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

## What was built

- **`assets/js/terrain_animation.mjs`** (pure, with Node tests in
  `assets/test/terrain_animation.test.mjs`): which cells hold an animated tile
  (`[index, frames]` with `frames > 1`), keeping that set in step with one edited
  cell, and when the clock should advance.
- **`MapCanvas` hook** (`map_hooks.js`): a `requestAnimationFrame` clock throttled
  to one step every 600 ms that redraws **only the
  animated cells**, at `frame = (phase + step) % frames`. The cell list is rebuilt
  on `tile_assets` and `map_reload`, and updated per cell in `applyTileValue`, which
  every paint, cycle, undo and redo goes through, so painting 0 → 601 adds a cell
  and undoing it removes it.
- **Pause and toggle:** the clock stops while the tab is hidden and restarts when
  it is shown. An **Animate terrain** checkbox in the Layers panel
  (`#animate-terrain`) turns it off, which redraws the animated cells at the
  server's phase, the same picture as before this story. The choice is kept in
  `localStorage` (`mirror.animateTerrain`); with no choice stored it starts off if
  the system asks for reduced motion.
- **The Lab** is left alone: its Phase control is still manual and the toggle is not
  shown there.
- **Scope:** every animated tile, not only the ocean sparkle, since the cell list
  comes from the atlas (601 and 31–33, the shore waves, channel, nodes, volcano and
  lake). A SAVE3 Arcanus has 300 animated cells and Myrror 317.

## Checked

In a real browser (the Docker image, in the built-in browser pane), driving the page's
hook, with a SAVE3 loaded, comparing every cell's pixels between frames:

- only animated cells change between ticks (300 of 300 on the first step; 0 static
  cells ever change), and the picture repeats after 4 ticks;
- a step inside the interval changes nothing (the throttle);
- toggling off with the checkbox restores exactly the picture as loaded, a stray
  tick does nothing while off, and the choice is stored;
- painting 0 → 601 adds a cell to the list and painting back removes it;
- Myrror builds its own list.

## The pace (measured 2026-10-07)

The first version stepped every 160 ms, a guess. Screenshots of the real game through
the DOSBox fork's API (a 601 ocean tile over 8 s, and the node sparkles over 7 s)
show the game steps its overland animation about **every 0.6 s** (13 intervals of
0.46–0.68 s, mean about 0.62; a 601 tile shows its 4 looks in turn). So the interval
is now **600 ms**, `ANIMATION_INTERVAL_MS` in `assets/js/terrain_animation.mjs`, shared
by the terrain canvas and the overlay canvas. Both take their frame from
`phaseAt(timestamp)`, the step the timestamp falls in, so they stay in step with
each other without sharing a timer.

## Seen

My checks stepped the clock by hand (the browser pane was hidden, so
`requestAnimationFrame` did not run). **Kevin has watched it run in a visible browser (2026-10-07):**
the terrain, the node sparkles and the enchanted roads all animate and "look great".
