# STORY-052: Decode the hero list, and show a wizard's heroes

**Parent:** [EPIC-010](../epics/EPIC-010-heroes.md)
**Status:** partly built (2026-10-15): the list, the unit link and the per-player hero table are read and shown on the wizard page (`Mirror.SaveFile.Heroes`); the ability bits, the experience thresholds, the units-panel rows, hiring and the Heroes-screen comparison are not done. *Original note:* open (2026-10-12). The list's layout is found (see below); the per-hero tables and hiring are not.
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

## Built (2026-10-15)

`Mirror.SaveFile.Heroes.for_wizard/2` reads a wizard's heroes from three places and `/wizard/:id` shows them (name, unit type, level, experience, tile, casting
skill, spells, item count):

- the wizard record's hero list at `+0x76` (6 x 28 bytes; **an empty slot is unit index -1**);
- the hero's unit record (type `+5`, hero slot `+6`, level `+12`, experience `+14`);
- **the per-player hero table at the start of the file: 6 x 420 bytes, 35 heroes x 12 bytes, indexed by unit type** (found 2026-10-15; the RAM map had it as
  "heroes, one block per player", the layout inside was not known): `+0` i16 (-20 for a hero the player has hired, 0 otherwise, *meaning unknown*), `+2..+5`
  ability bits (*not decoded*), `+6` casting skill, `+7..+10` four spell numbers (0 none), `+11` padding.

Checked on `SAVE2.GAM` (no game session): Sir Harold is unit 50 (type 31, level 2, 27 xp, at 7,17 Arcanus) and the rival's Rockfist is a Bahgtru (type 6) at 23,23;
both carry the -20 marker in their own player's table; every hero with spells in the table has numbers inside its realm's range (Chaos 81 to 120, Death 161 to
200, Nature 1 to 40). Sir Harold and Rockfist have no spells, as expected for warriors.

Not done: the ability names (a bit table, needs the game's Heroes screen), a hero's casting skill vs the game's number (the byte may be a base, not the shown value), the
experience thresholds (step 3), the units-panel rows, and what the -20 means.
