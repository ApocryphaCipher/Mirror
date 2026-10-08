# STORY-020: Structure detail editors (city / lair / unit)

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** later (2026-10-07). The records for the first slice are decoded for reading (cities:
name, owner, race, population; units: type, owner; sites: kind, guards, rewards, see
[kazzmir-save-layouts.md](../reference/kazzmir-save-layouts.md)); what it needs next is each
editable field checked in the real game, one at a time.
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
