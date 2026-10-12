# STORY-020: Structure detail editors (city / lair / unit)

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** later (2026-10-07). The records for the first slice are decoded for reading (cities:
name, owner, race, population; units: type, owner; sites: kind, guards, rewards, see
[kazzmir-save-layouts.md](../reference/kazzmir-save-layouts.md)); what it needs next is each
editable field checked in the real game, one at a time.
**Progress (2026-10-11), first slice built: the 🏙️ City tool.** Click a city in edit mode: a panel shows its
name, size, race, owner (wizard name and banner), plane and position, garrison count, walls, buildings
(and replaced ones), enchantments with their casters, and road links; name and population can be edited in
the panel, each Apply one undo step (`Structures.edit_city/3`; logic in `MirrorWeb.CityPanel`).

**Real-game check (slot 6, vault checkpoints 90 and 91):** the edited names and population bytes load into the
game's memory unchanged, and the game accepts them (Kevin: Hackerville pop 12 and Zürich pop 20 both
Villages, rebels from the sudden growth, "nothing unusual").
- **Names must be ASCII.** "Zürich" was saved with the Latin-1 byte `fc`, and the game showed "Zrich": the
  font has no "ü". Names are now limited to printable ASCII, 1 to 13 characters.
- **Size class is not recomputed.** The size byte (`+19`) stayed 2 for pop 12 and 20, on load and after an
  End Turn, and across all saves here it overlaps in population (size 1 at pop 1-7, size 2 at 5-12), so it
  is not a function of population. The tool leaves it alone. Setting it, if wanted, is a separate edit.
- **Not checked:** the building names other than 26, 29 and 35 (by order, matching Kevin's cities), the
  25 limit on population, and population above a city's food.
- Race names are checked for Dwarf, Halfling and Lizardman; the panel's race table fixes an earlier
  off-by-one bug in the first draft (a `~w` sigil split "Dark Elf").

**Not done:** editing owner, race, buildings or enchantments; the panel in View mode as an inspector; lairs
and units (the other panels in this story).
**Size:** large (do incrementally)

## What to do

A side panel when a structure is selected in edit mode:

- **City**: name, owner, race, population, buildings (later), garrison.
- **Lair / ruin / temple**: type, guardians, treasure, cleared flag.
- **Unit**: type, owner, experience/level, enchantments (later).

Start read-only (it doubles as an inspector in View mode), then make fields
editable one at a time as each byte is verified.

## Definition of done (first slice)

- Selecting a city shows its decoded fields read-only, and name and
  population can be edited and survive a round trip into the real game.
