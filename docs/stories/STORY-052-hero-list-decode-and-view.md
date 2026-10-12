# STORY-052: Decode the hero list, and show a wizard's heroes

**Parent:** [EPIC-010](../epics/EPIC-010-heroes.md)
**Status:** open (2026-10-12). The list's layout is found (see below); the per-hero tables and hiring are not.
**Size:** medium to large
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-12

## What to do

0. **Found (2026-10-12):** the list is 6 × 28 bytes at `+0x76` (unit index, 14-byte name, 3 item indexes, 3 slot types); checked on SAVE2. See [wizard-heroes-diplomacy-items.md](../reference/wizard-heroes-diplomacy-items.md). The two per-hero tables kazzmir reads (35 heroes' level, abilities, casting skill, spells; 35 names with experience) and the game's `HERODATA.LBX` (150 records of 10 bytes, *guess:* the heroes' template) remain.
1. **Decode the rest of** each wizard's hero list: where it is, how many slots, what each entry holds, the hero's name (a hero is
   renamed in the game), and how the unit record's hero slot (`+6`) ties to it. *Unknown:* all of it beyond `+6`. Read
   kazzmir's loader first; confirm in the real game by hiring a hero and diffing memory (the DOSBox fork,
   [live-ram-map.md](../reference/live-ram-map.md)). Write the layout into `docs/reference/` with two sources.
2. **Show** a wizard's heroes: on the wizard page (EPIC-009's STORY-047) and on the units panel's rows (name, level name
   such as "Champion", experience to the next level).
3. **Hero levels:** record the experience thresholds (the saves show a hero at level 2 with 25 xp, so the table is not the
   normal unit's), checked against the game's own unit screen.

## Definition of done

A documented layout with two sources; the page and the units panel agree with the game's Heroes screen for one real save.
