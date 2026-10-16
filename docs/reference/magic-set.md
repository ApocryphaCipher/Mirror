# MAGIC.SET: the slot names

The game's Load Game screen shows a name for each slot. The names live in `MAGIC.SET` in the game folder, next to `SAVE1.GAM` to `SAVE9.GAM`. A save whose slot has no name still loads, but the screen shows it **blank** (Kevin, 2026-10-16), which looks like a broken save to anyone who does not know that.

## Layout (checked in four copies of the file, 2026-10-16)

The file is 466 bytes in all four (GOG `MAGIC` and `MagicCom`, the old CD install in `~/.mirror_assets/MAGIC`, and a Freya test game).

| Offset | Bytes | What |
| --- | --- | --- |
| `0x00` | 64 | 32 little-endian words of settings. *Not decoded; Mirror never touches them.* |
| `0x40` | 8 × 20 | The names of slots 1 to 8, zero padded. Slot *n* starts at `0x40 + 20 × (n − 1)`. Unused slots are all zeros. |
| `0xE0` | 242 | The rest. *Not decoded.* |

Slot 9 (the autosave) has no name here. The longest names the game itself wrote are 18 characters ("Freya - Settlement"), so *guess:* the name box stops at 18.

## What Mirror does with it

When the browser saves into slot *n* (EPIC-012), and that slot's name in `MAGIC.SET` is **empty**, Mirror writes `Mirror Edit Slot n` (18 characters). A name that is already there, whoever wrote it, is never changed. If the file is missing or shorter than `0xE0`, nothing is done (Mirror does not invent a `MAGIC.SET`, because its settings words are unknown). Before the first change Mirror copies the file to `MAGIC.SET.mirror-backup`; an existing backup is kept. The code is `withSlotName` in `assets/js/save_slots.mjs` (Node tests in `assets/test/save_slots.test.mjs`).

**Checked in the game (Kevin, 2026-10-16):** after a save from Mirror into the empty slot 8, the game's Load Game screen shows "Mirror Edit Slot 8" on row 8, with the other seven names as before.

**What the game does with the names (seen the same day):** when it starts, it blanks the name of every slot that has no save file (slot 8 went from "SAVE 8" to empty after `SAVE8.GAM` had been moved away), and it keeps the names of slots that have one. So a save written into an empty slot comes out blank unless Mirror names it. *Guess:* the game also rewrites `MAGIC.SET` when it quits, which would undo Mirror's edit if the game is open while Mirror saves, so save from Mirror with the game closed (not checked).
