# EPIC-010: Heroes

**Status:** STORY-053 done (2026-10-15; transfer and dismiss dropped by decision); STORY-052 partly built (the wizard page lists heroes; ability names, experience thresholds and units-panel rows are open)
**Owner:** [Kevin](https://github.com/KevinAsbury)
**Requested:** 2026-10-12, split out of EPIC-009 (wizard editing): heroes get their own epic.

## The idea

A hero is a unit with a place in his wizard's hero list: the unit record's hero slot (`+6`) points into it, and the
wizard record presumably holds the list itself and the hero's name. Heroes level on a longer table than normal units
and carry artifacts (EPIC-011). Today Mirror shows a hero as a unit (type 0 to 34, level, experience, owner) and
the unit editor edits his level, experience and damage; it **refuses to change a hero's owner** (`:hero_owner`), the
correct stop until the hero list is decoded (STORY-020).

## What is known, and what is not

- **Known:** unit types 0 to 34 are heroes; the unit record's `+6` is the hero slot (kazzmir's reading, never checked
  on its own); in the saves here every hero's level and experience are on the unit record, and the game works the
  level out from experience at End Turn (STORY-020, 2026-10-12, checked for a normal unit; **not** for a hero).
- **Found (2026-10-12), [wizard-heroes-diplomacy-items.md](../reference/wizard-heroes-diplomacy-items.md):** the hero list is **6 entries of 28 bytes at `+0x76` of the wizard record**: the unit's index, the hero's own given name (14 bytes), three item indexes and three slot types. Checked in SAVE2: Jafar's entry 0 is unit 51, Sir Harold. kazzmir's loader also reads a per-hero table of 35 (level, abilities, casting skill, spells) and a 35-entry table of names and experience; those are not placed yet.
- **Unknown:** what a hero's death or dismissal writes, how a hero is hired, hero levels' experience thresholds (*guess:* a longer table than the
  normal unit's, from the saves: level 2 at 25 xp), what a hero's death or dismissal writes, and how a hero is
  hired or summoned. Start from kazzmir's loader and a diff of a game where a hero is hired.

## Stories

- [STORY-052](../stories/STORY-052-hero-list-decode-and-view.md): decode the hero list; show a wizard's heroes (on the wizard page, EPIC-009, and the units panel)
- [STORY-053](../stories/STORY-053-hero-editing.md): edit a hero: name, experience and level, dismiss, give to another wizard; lifts the unit editor's `:hero_owner` refusal

Related: [EPIC-009](EPIC-009-wizard-editing.md) (the wizard page shows the heroes), [EPIC-011](EPIC-011-artifacts.md) (what they carry).
