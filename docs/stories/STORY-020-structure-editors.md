# STORY-020: Structure detail editors (city / lair / unit)

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** later; blocked on the matching record layouts being decoded
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
