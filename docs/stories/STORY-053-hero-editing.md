# STORY-053: Edit a hero

**Parent:** [EPIC-010](../epics/EPIC-010-heroes.md)
**Status:** partly built (2026-10-15): name, level, experience and damage are editable from the wizard page; giving a hero to another wizard, dismissing and adding are not built, and nothing was loaded in the real game. *Original note:* open (2026-10-12), after STORY-052
**Size:** medium
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-12

## What to do

- Edit a hero's **name**, **experience** (and with it the level, which the game recomputes at End Turn) and **damage**.
- **Give a hero to another wizard:** write the unit's owner and move the entry between the two hero lists, with the rules
  the unit editor already has (one owner to a tile, not into another owner's city) plus a free slot in the new list.
  This lifts `Structures.edit_units/3`'s `:hero_owner` refusal for the case the list handles.
- **Dismiss** a hero, and **add** one (a hero unit type 0 to 34 into a free slot): *open question* whether to build this at all;
  hiring has game rules (fame, gold) that the save does not enforce.

## Definition of done

Each edit loaded in the real game, read back from memory, shown correctly on the Heroes screen and surviving one End Turn;
tests as in STORY-048.

## Built (2026-10-15)

In edit mode each hero on `/wizard/:id` has a small form: **name** (1 to 13 printable ASCII characters, the list entry's 14 bytes are NUL-padded), **level**,
**experience** and **damage** (the unit's `+12`, `+14`, `+17`, with the limits `Structures.edit_units/3` already has). `Structures.edit_hero/4` does the write; one
apply is one undo step, like the other wizard edits. The game works the level out from experience again at End Turn, so experience is the lasting field.

Not done, and why:

- **Give a hero to another wizard:** needs the entry moved between two hero lists, the unit's hero slot (`+6`) rewritten, the items carried over and the
  unit editor's tile rules; none of that has been seen in the real game, so `edit_hero/4` and the unit editor still refuse an owner change (`:hero_owner`).
- **Dismiss and add:** the open question stands (hiring has rules the save does not enforce).
- **The real-game check** (Heroes screen, one End Turn) from the definition of done: not run. *Guess:* a renamed hero shows his new name on the Heroes screen, as
  the list entry holds the name; unchecked.
