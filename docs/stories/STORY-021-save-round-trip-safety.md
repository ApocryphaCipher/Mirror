# STORY-021: Save round-trip safety

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** in progress — automated checks done, DOSBox visual sign-off pending.
**Size:** small–medium

## What to do

- **Golden test**: load then save with no edits, and the output is
  **byte-identical** to the input for every save we have. Tag it to skip
  when game files are absent, like `TerrainLbxTest`.
- **Minimal diff**: after an edit, only the bytes that edit owns change.
  Add a test helper that diffs two saves by block (terrain, cities, units…).
- **Never overwrite by default**: Save as a new name; the existing backup
  behaviour of `SaveFile.write` stays.
- **Real-game acceptance**: the GOG release includes DOSBox. Document how
  to drop an edited save in and load it, and use that as the sign-off step
  for each editing story. (See `docs/reference/real-game-acceptance.md`)

## Definition of done

- The round-trip test is green for `SAVE1`, `SAVE2`, `SAVE9` and `TEMPLATE`.
- One hand-edited save (a single terrain tile) loads in the real game via
  DOSBox.

## Outcome so far

- The golden round-trip test is green for all 4 saves.
- The minimal diff test is green, proving single tile edits only modify 2 bytes.
- The `SaveFile.write/3` backup behaviour test is untouched and remains green.
- Real-game acceptance doc written at `docs/reference/real-game-acceptance.md`.
- Prepared a hand-edited save from `SAVE2.GAM` at `~/.mirror/dev/DOSbox/save-edits-2026-09-27/SAVE2-edited.GAM` with its original next to it.
  - Tile (10, 10) on `:arcanus` was changed from value 183 to 266.
- **Pending:** A human needs to load `SAVE2-edited.GAM` via DOSBox and verify the edit visually to sign off on this story.
