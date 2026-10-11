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
**Test saves for the real-game check (2026-10-10, not yet loaded).** Built from SAVE1 with the
code above, in `~/DOS/MAGIC` (what the slots held before is in `~/.mirror/dev/DOSbox/backups/`,
`SAVEn-pre-story019-2026-10-10.GAM`). Look for the structure in the new place, working normally,
and the old tile empty:

| Slot | Move | Also check |
| --- | --- | --- |
| 4 | Breslau (neutral city) (26, 21) to (29, 18) | opens its city screen; no garrison on this one |
| 5 | Deventor, Freya's capital (38, 21) to (35, 18) | fortress and summoning circle are there; the 2 garrison units went along; a turn ends without trouble |
| 6 | Tower of Wizardry (33, 7) to (39, 9) | a tower on both planes; its guards (Unicorns x3, Guardian Spirits x4) on entering |
| 7 | the lair at (18, 29) to (15, 26) | its guards and treasure unchanged |

**Real-game results (2026-10-10, Kevin at the keyboard, fork API read-back, checkpoints 73-77
in vault collection `mom-live-2026-10-10`).** Built from Kevin's "Jafar the Hacker" save.
- **Slot 3, neutral city with garrison: passes.** The game's RAM holds the city at the new tile and
  both garrison units there; units, fortress, towers, encounters, nodes and every map layer equal
  the file. Kevin: city is in the new spot.
- **Slot 4, capital, same plane: passes.** Circle and fortress follow; RAM equals the file; End
  Turn ran with no trouble. The city-road-link question is **still open**: that save has no roads,
  so the link bytes were zero before and after.
- **Slot 5, capital to the other plane (Arcanus to Myrror): passes.** City, circle and fortress all
  read (9, 18, plane 1) in RAM; a turn passed. Units standing next to the city were left behind, as
  designed: only units on the city's own tile move.
- **Slot 6, tower: passes, with a lesson.** The tower record and both encounter sides read the new
  tile in RAM. The destination was land on Arcanus but **ocean on Myrror**, and the game loaded it
  and let Kevin clear it with flying units, and shows the units on both planes. A tower should be
  land on both planes: `move_tower/3` now returns `warnings: [water: :myrror]` for that.
  Land units can't reach such a tower (water-walkers and flyers can).
- **Slot 7, abandoned keep: loads, bytes verified; not looked at on screen.** In RAM the keep is the same
  record (kind 7, intact, guards and treasure unchanged) at the new tile, with nothing at the old tile, and
  encounters, units and towers equal the file (checkpoint 79). Kevin did not confirm it on the map.
- **Slot 8, city, tower and keep together: loads, bytes verified** (checkpoint 80, 2026-10-11).
  RAM has Hialanth at (9, 13), the tower at (8, 11) and the keep at (15, 20); encounters, units and
  towers equal the file. The tower's new tile is ocean on Myrror again (the save builder only checked
  Arcanus), which the game tolerates. Not looked at on screen.
- **Kevin saw the moved tower, once cleared, lit with an eerie green light** (2026-10-10): the owned
  picture, see STORY-046.

**Slice 2 (2026-10-11): the Move city tool.** In edit mode, 🏰 Move city: click a city, then click
where it goes (right-click or clicking it again cancels). It calls `Structures.move_city/3` and is one
undo step: `Editor.apply_record/4` puts a *record* entry in the same history as tile strokes, undo/redo
swap the save's raw bytes, Discard restores them, and Save as writes them. The toolbar counts moves
next to tile changes. Logic is in `MirrorWeb.MoveTool`; tests are LiveView tests on the synthetic save.
Checked in the browser against a real save (tool shows, note text); the click-on-a-real-city path is
covered by the LiveView tests, not yet clicked by a person.

**Not done:** towers, lairs, nodes and units in the UI, a highlight on the picked-up city,
the Structures edit layer and select-then-click UI, undo/redo for record edits,
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
