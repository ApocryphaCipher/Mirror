# STORY-010: Cities on the map

**Parent:** [EPIC-004](../epics/EPIC-004-overland-map-features.md)
**Status:** open, blocked on STORY-006 (city art) for the drawing half;
parsing can start now
**Size:** medium

## What to do

1. **Parse** the cities block: `0x008aac`, 100 × 114 bytes, live count at
   `0x0009e0`. Fields cross-validated by momedit: `+15` x, `+16` y,
   `+17` plane, `+18` owner, `+20` population. Name is at the start of
   the record (verify).
2. **Owner colour**: owner → wizard record (`0x0009e8 + n × 0x4c8`) →
   banner colour at `+0x16`.
3. **Draw** `MAPBACK.LBX` `MAPCITY` (frame by city size, colour by owner;
   check how the real game tints it) on the city's tile, with the name
   label optional.
4. Walled / enchanted variants are a follow-up.

## Definition of done

- All cities in `SAVE1.GAM` appear on the right tiles and planes, in their
  owner's colour, matching the real game's overland view.
