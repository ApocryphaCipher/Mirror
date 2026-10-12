# STORY-050: Relations between wizards: peace, war, attitude

**Parent:** [EPIC-009](../epics/EPIC-009-wizard-editing.md)
**Status:** open (2026-10-12), starts with a decode
**Size:** large (the decode decides)
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-12 ("a relationship editor", "peace/war tags")

## What to do

1. **Decode.** Where the save keeps, for each pair of wizards, the diplomatic state (peace, war, an alliance or treaty
   if the game has one), the attitude or relation number the AI uses, and any treaty timers. *Unknown:* all of it. Start
   with kazzmir's loader (`load.go`), then confirm by diffing two saves of the same game that differ only in a diplomacy
   event (Kevin makes peace with a rival, or breaks a treaty, and saves), and read the changing bytes from the game's memory
   with the DOSBox fork ([live-ram-map.md](../reference/live-ram-map.md)). Write it up in `docs/reference/`.
2. **Show it** on each wizard's page: for every other wizard, the state as a tag (Peace, War, ...) and the attitude, with a
   link to that wizard.
3. **Edit it**: set the state and attitude for a pair. Check whether the game keeps the pair's two directions in step (A's
   view of B and B's view of A) or whether both have to be written; the editor writes both if both exist.

## Definition of done

A documented layout with two sources; one edited relation loaded in the real game and visible on its Diplomacy screen, and
the AI behaving as the new state says over one End Turn (it does not break a peace on the spot, or if it does, that is noted).
