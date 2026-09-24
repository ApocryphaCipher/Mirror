# STORY-011: Towers, fortresses, lairs, ruins and other sites

**Parent:** [EPIC-004](../epics/EPIC-004-overland-map-features.md)
**Status:** open, ready. The site art is catalogued (STORY-006). Layouts
for fortresses (checked), towers (no plane byte) and encounter zones
(kind table and sprite per kind) are in
[kazzmir-save-layouts.md](../reference/kazzmir-save-layouts.md). Checked on SAVE1: each node
kind's realm matches its node (all 30). Tower defenders are encounter
records on both planes (0–5 Arcanus, 6–11 Myrror). Open: the guard-count
nibbles and the `+15` explored-by flags.
**Live RAM (2026-09-24):** guard nibbles settled; several kinds checked on screen; open: `+15` and the cleared look. See [the evaluation](../notes/2026-09-24-live-ram-evaluation.md).
**Size:** medium

## What to do

1. **Decode** (layouts unknown, verify each; see [../reference/overland-sprites-and-save-blocks.md](../reference/overland-sprites-and-save-blocks.md)):
   - Towers of Wizardry: `0x006610`, 6 × 4 bytes
   - Wizard fortresses: `0x0065f8`, 6 × 4 bytes
   - Encounter zones: `0x006628`, 102 × 24 bytes (lairs, ruins, ancient
     and fallen temples, keeps, mounds…). Need type, x/y/plane, and
     whether it's been cleared.
2. **Draw** the `MAPBACK.LBX` `SITES` icons: unowned/owned tower, mound,
   temple, keep, ruins, fallen temple. The fortress art is probably
   elsewhere; find it in STORY-006.
3. Towers appear on both planes at the same x/y. Check the render agrees.

## Definition of done

- Every tower, fortress and encounter zone in `SAVE1.GAM` is drawn with the
  right icon on the right tile, matching the real game.
