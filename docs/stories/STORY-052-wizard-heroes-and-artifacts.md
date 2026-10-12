# STORY-052: Heroes and artifacts

**Parent:** [EPIC-009](../epics/EPIC-009-wizard-editing.md)
**Status:** open (2026-10-12), starts with a decode; lowest priority in the epic
**Size:** large
**Raised by:** Claude, 2026-10-12, so that two open edges have a home: heroes were left out of the unit editor, and a unit's items are not decoded.

## What to do

1. **Decode** each wizard's hero list (the six slots, which unit record each points to; a unit's `+6` is its hero slot) and the
   items a hero carries and the wizard keeps (the artifacts: name, the power list, the slots they fit). *Unknown:* all of it
   beyond the unit's own hero-slot byte.
2. **Show** them on the wizard page, with a hero's level, experience and items.
3. **Edit**: a hero's name and experience first (the level is recomputed by the game from experience, STORY-020), then give a
   hero's owner a path (it needs the hero list to move too), then items.

Until this lands, the unit editor refuses to change a hero's owner (`:hero_owner`), which is the correct stop.

## Definition of done

The layout documented with two sources and one hero edit checked in the real game over an End Turn.
