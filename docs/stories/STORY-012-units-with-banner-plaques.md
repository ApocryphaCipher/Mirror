# STORY-012: Units on the map with banner-colour plaques

**Parent:** [EPIC-004](../epics/EPIC-004-overland-map-features.md)
**Status:** open, blocked on STORY-006 (figure + plaque art) and on
verifying the unit record layout
**Size:** medium–large

## What to do

1. **Decode** the units block: `0x00b734`, up to 1009 × 32 bytes, live
   count at `0x0009e2`. Need x/y/plane, owner, unit type at minimum.
   Verify against units you can identify in a known save (e.g. the
   starting spearmen next to each capital).
2. **Unit figure**: `UNITS1.LBX` (120) + `UNITS2.LBX` (78) `STATFIG` entries,
   18×16. Confirm the unit type → entry mapping (likely a straight index
   across both files).
3. **Plaque**: the coloured backing the figure sits on, in the owner's
   banner colour (wizard `+0x16`; neutral/rampaging monsters use the
   neutral colour). The `MAPBACK.LBX` `SITES` blue/green/purple/red/yellow/
   neutral entries are the likely source.
4. **Stacks**: one plaque + figure per tile (the real game shows the top
   unit of a stack). Units inside cities/towers are hidden, as in the game.

## Definition of done

- Every visible stack in `SAVE1.GAM` shows the right unit figure on the
  right owner-coloured plaque, on the right tile, toggleable via STORY-009.
