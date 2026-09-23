# STORY-019: Select and move structures and unit stacks

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** blocked on EPIC-004 decode stories (010 cities, 011 sites, 012 units; STORY-008 for nodes)
**Size:** medium–large

## What to do

- **Structures** / **Units** edit layers: click to select what's on a tile
  (city, lair/ruin/temple, tower, node, fortress, unit stack), then click a
  destination, on either plane.
- A city moves with its garrison. Selecting the same city twice selects
  just its units (as in MMS). Moving a capital moves its fortress and
  summoning circle.
- Allow placements the game tolerates (cities or lairs on ocean) but warn
  about side effects (e.g. land units can't defend there without a road).
- Keep every cross-reference consistent: unit x/y, city x/y, wizard
  summoning-circle coordinates, node aura tiles if a node moves.

## Definition of done

- Moving each kind of structure in `SAVE1.GAM` and loading the result in
  the real game shows it in the new place, working normally.
