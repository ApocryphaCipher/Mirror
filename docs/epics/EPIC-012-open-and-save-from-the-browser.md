# EPIC-012: Open and save from the browser

**Status:** planned (2026-10-15), not started
**Owner:** [Kevin](https://github.com/KevinAsbury)
**Requested:** 2026-10-15

## The idea

Today a user has to copy a save into `~/.mirror/game`, type its path into a box in the map header, and copy the edited file back out. It is clunky, and it is not clear
whether an edit saves itself (it does not; **Save as** does). The fix: the user picks their **game folder once**, and the top bar of every page shows the **save slots** as
buttons (green = a save is there, grey = empty). Click a slot to load it, pick a slot to save to. No paths, no file names, no copying.

## Decisions (Kevin, 2026-10-15)

- **Chrome (and Edge) only.** The folder picker is the browser's File System Access API (`showDirectoryPicker`), which Chrome and Edge have. Safari and Firefox users are on their own
  (no second code path is built for them; the old path box can stay as a fallback until the new flow has proved itself, STORY-061).
- **Pick the game folder once.** The top bar shows slots 1 to 8 as small buttons: filled (a `SAVEn.GAM` exists) or empty. (Slot 9 is the game's autosave and its Load screen cannot pick it, see AGENTS.md section 9, so it is not offered for loading
  the way slots 1 to 8 are; whether to show it greyed is open.) Click a filled slot to load it. To save, pick a slot.
- **Overwriting a slot is allowed, with a warning.** This **replaces** the rule "never overwrite the save that was loaded" (AGENTS.md section 9, `SaveFile.write/3`). The new rule: saving into a filled slot asks first, in the page (never `window.confirm`, AGENTS.md section 8).
- **A plain "unsaved changes" badge** in the top bar, so a wizard edit is clearly not saved until the user saves.
- The top bar is **page-wide** (map, wizard pages, Lab), not part of the map header.

## How it works (the plan, none of it built)

The browser holds the folder handle and reads and writes the files; the server never sees the user's disk, so this works the same from Docker. Load: the page reads `SAVEn.GAM` and sends its bytes to the
server's session (about 123 KB). Save: the server builds the file's bytes and sends them to the page, which writes them into the chosen slot. The server keeps the save and its edit history in memory as it does now; only where the bytes come from and go to changes.

## Open questions

- **A backup when overwriting.** *Suggestion:* before replacing a filled slot, the page first writes the old bytes to `SAVEn.GAM.mirror-backup` (the game ignores the file), so an overwrite is never final. Needs Kevin's yes.
- **Remembering the folder.** The browser can keep the folder handle between visits (IndexedDB), but Chrome asks the user to re-allow access each visit (one click). *Guess:* acceptable.
- **Slot labels.** *Guess:* a save carries its own name or turn number that could label the buttons on hover; not checked. Plain slot numbers are enough for the first version.
- **What happens to the save-path logic on the server** (`state.save_path`, "Save as" suggestions, the overwrite refusal): it is replaced or removed. Tests that cover it change with it.
- **A saved game opened by the game while Mirror has it open:** the slot buttons should refresh when the page regains focus.

## Stories

- [STORY-058](../stories/STORY-058-top-bar-and-unsaved-badge.md): the page-wide top bar and the unsaved-changes badge
- [STORY-059](../stories/STORY-059-pick-folder-and-load-slot.md): pick the game folder, show the slots, load a slot
- [STORY-060](../stories/STORY-060-save-to-slot.md): save to a slot, with an overwrite warning
- [STORY-061](../stories/STORY-061-retire-the-path-box.md): retire the path box and the old save-path rules

Order: 058, then 059, then 060, then 061.
