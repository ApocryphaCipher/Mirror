# STORY-021: Save round-trip safety

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** Done (2026-09-27).
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

## Outcome

- The golden round-trip test is green for all 4 saves (`SAVE1`, `SAVE2`,
  `SAVE9`, `TEMPLATE`).
- The minimal diff test is green, proving single tile edits only modify 2 bytes.
- The `SaveFile.write/3` backup behaviour test is untouched and remains green.
- Real-game acceptance doc written at `docs/reference/real-game-acceptance.md`.
- **Real-game sign-off, done 2026-09-27:** the hand-edited save
  (`SAVE2.GAM` with tile (10, 10) on `:arcanus` changed 183 → 266,
  prepared at `~/.mirror/dev/DOSbox/save-edits-2026-09-27/SAVE2-edited.GAM`)
  was dropped into slot 5 and loaded in the real game via DOSBox
  (0.74-3, `~/DOS/MAGIC`) — Kevin drove the DOS/game-menu side, an agent
  verified from the DOSBox Staging fork's read-only memory API
  (`docs/reference/live-ram-map.md`): the game accepted the save with no
  corruption error, and the live RAM word at the resolved terrain
  address (found by searching a live 16 MB dump for a 64-byte chunk
  around the edit; matched uniquely at RAM `0x72ad8`, delta `0x6FF98`
  from the save offset — the same delta recorded in
  `live-ram-map.md`, so that mapping still holds a session later) read
  **266**, matching the file exactly. gama checkpoints 49 (baseline:
  Kevin's own SAVE3 "Freya" game, confirmed by wizard/city data, to
  rule out a false positive from checkpointing the wrong save) and 50
  (SAVE5 loaded, with screenshot) are in the `mom-live-2026-09-27`
  collection of the Evi vault.
