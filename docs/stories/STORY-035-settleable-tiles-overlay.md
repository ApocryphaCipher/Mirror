# STORY-035: Highlight the tiles where a city can be built

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** open, nice-to-have
**Size:** small to medium
**Requested by:** [Kevin](https://github.com/KevinAsbury), 2026-09-24
**Builds on:** [STORY-034](STORY-034-surveyor.md) (Surveyor)

## Goal

A map mode (an overlay toggle, like the Layers checkboxes) that tints
every tile where a new city could be built. Today you find them one tile
at a time with the Surveyor card.

## What "settleable" means

It's exactly the Surveyor's check, in the game's order (see
[surveyor-formula.md](../reference/surveyor-formula.md#the-tile-panel)).
A tile is out if it is any of these:

- water;
- a Tower of Wizardry (either plane);
- a node;
- an intact site;
- within 3 tiles of another city on the plane (the larger of the x and y
  gaps, with x wrapping).

The game also shows nothing for an unexplored tile. Decide whether the
overlay follows the fog, or shows the whole map like the rest of Mirror.

## Ideas

- **Grade the tint** by the site's Maximum Pop (or by production or
  gold), so good sites stand out, not just legal ones. This is
  `Mirror.Surveyor.city_resources/5`.
- **Hovering** a tinted tile already shows its full City Resources in the
  Surveyor card.
- **Recompute on edits.** Edit mode changes terrain and moves things, so
  the overlay should follow.

## Implementation notes

- `Mirror.Surveyor`'s settle check is private (`settle_check/7`). Expose
  it as a small public function, e.g. `settleable?/6`, rather than going
  through `panel/6` for all 2,400 tiles per plane.
- Grading means 2,400 `city_resources` calls per plane. That's probably
  fine once per load or edit, but measure before optimising (the claimed
  catchment set can be built once, not per tile).
- Draw it like the other overlays: push the tiles (or a per-tile grade)
  as an `overlay_data` layer, and draw it client-side.

## Done when

- A Layers toggle shows the settleable tiles on the current plane.
- The tinted tiles agree with the Surveyor card on hover, including a
  test that the tile at distance 3 from a city is out and distance 4 is
  in.
- It updates after an edit.
