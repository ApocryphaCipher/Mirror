# STORY-019: Select and move structures and unit stacks

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** open, no longer blocked (2026-10-07): the decode stories (010 cities, 011 sites,
012 units, 008 nodes) are Done, so the records can be read. What is still unproven is
writing them: each moved structure's x/y and every cross-reference has to load cleanly in the
real game, one kind at a time.

**Progress (2026-10-10), slice 1: the record layer, not yet in the UI and not yet seen in the game.**
`Mirror.SaveFile.Structures` (`lib/mirror/save_file/structures.ex`, pure raw-in raw-out) has
`move_city/3`, `move_tower/3` and `move_encounter/3`, with unit tests on synthetic saves.
Checked on the real SAVE1 (read-only, output to the scratchpad): moving the capital one tile
changes exactly five bytes: the city x, the wizard's summoning circle x, the fortress x and the
two garrison units' x. A tower moves its tower record, both encounter sides and any units on
its tile. "One kind at a time" means each kind gets its own real-game check
(real-game-acceptance.md), because each carries different cross-references; it does not mean
one building per code change.
**Not done:** the Structures edit layer and select-then-click UI, undo/redo for record edits,
**nodes** (a node is its terrain tile, so it needs a terrain move too, plus aura tiles and
its guardian record), and units moved on their own (stack moves). **Left alone, unchecked:**
a city's road links (`+101`; whether the game recomputes them is unknown, results carry
`stale: [:city_road_links]`) and any go-to target a unit record may hold.
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
