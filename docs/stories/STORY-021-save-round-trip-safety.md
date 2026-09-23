# STORY-021: Save round-trip safety

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** open, ready to start. Do it before any editor ships.
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
  for each editing story.

## Definition of done

- The round-trip test is green for `SAVE1`, `SAVE2`, `SAVE9` and `TEMPLATE`.
- One hand-edited save (a single terrain tile) loads in the real game via
  DOSBox.
