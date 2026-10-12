# STORY-053: Edit a hero

**Parent:** [EPIC-010](../epics/EPIC-010-heroes.md)
**Status:** open (2026-10-12), after STORY-052
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
