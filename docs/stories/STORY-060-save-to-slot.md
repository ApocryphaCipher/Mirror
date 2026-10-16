# STORY-060: Save to a slot, with an overwrite warning

**Parent:** [EPIC-012](../epics/EPIC-012-open-and-save-from-the-browser.md)
**Status:** done (2026-10-16): saved from Mirror into an empty slot with Chrome's real picker, loaded in the game, next turn advanced (Kevin). Replace was checked on the real folder too: the confirmation, the overwrite and the `.mirror-backup` file (its bytes were identical to the new save, both being unedited copies, so the "holds the old bytes" part was shown only with the fake folder). The backup is kept once (the first one stays), see the epic
**Size:** medium
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-15

## What to do

A **Save** control in the top bar: the user picks a slot (1 to 8; **slot 9, the autosave, can be loaded but never saved to**, Kevin 2026-10-15), the server builds the file's bytes, the page writes them to `SAVEn.GAM` in the chosen folder.

- A **filled** slot asks first, in the page: "Replace SAVE3.GAM?" (never `window.confirm`). An empty slot saves straight away.
- **Decided (Kevin, 2026-10-15):** write the old bytes to `SAVEn.GAM.mirror-backup` before replacing, so an overwrite is never final. Test that the backup holds the old bytes and that a failed backup stops the save.
- The write goes to a temporary name and is renamed, as `SaveFile.write/3` does today (so a crash cannot leave half a save); *guess:* the File System Access API's writable stream is already atomic on close, check.
- After a save: the badge clears, the slot buttons refresh, and the message says which slot was written and that the game can load it.
- This **replaces** the rule in AGENTS.md section 9 that a save is never written over the one that was loaded; update AGENTS.md and the `:would_overwrite_original` refusal in the same change.

## Definition of done

- Tests for the byte-building side (the same bytes the current Save as writes). A real-game check: save to a slot from Mirror, load it in DOSBox, as in [real-game-acceptance.md](../reference/real-game-acceptance.md).
- The overwrite warning and the backup (if chosen) checked in Chrome.
