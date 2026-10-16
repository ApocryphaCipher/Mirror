# EPIC-012: Open and save from the browser

**Status:** 058, 059 and 060 built (2026-10-16); 061 waits for Kevin. Not yet tried against a real Chrome folder picker: see "What was built"
**Owner:** [Kevin](https://github.com/KevinAsbury)
**Requested:** 2026-10-15

## The idea

Today a user has to copy a save into `~/.mirror/game`, type its path into a box in the map header, and copy the edited file back out. It is clunky, and it is not clear
whether an edit saves itself (it does not; **Save as** does). The fix: the user picks their **game folder once**, and the top bar of every page shows the **save slots** as
buttons (green = a save is there, grey = empty). Click a slot to load it, pick a slot to save to. No paths, no file names, no copying.

## Decisions (Kevin, 2026-10-15)

- **Chrome (and Edge) only.** The folder picker is the browser's File System Access API (`showDirectoryPicker`), which Chrome and Edge have. Safari and Firefox users are on their own
  (no second code path is built for them; the old path box can stay as a fallback until the new flow has proved itself, STORY-061).
- **Pick the game folder once.** The top bar shows slots 1 to 9 as small buttons: filled (a `SAVEn.GAM` exists) or empty. Click a filled slot to load it. **Slot 9 (the game's autosave) can be loaded but never saved to**: Mirror offers it for loading and refuses it as a save target.
- **Overwriting a slot is allowed, with a warning.** This **replaces** the rule "never overwrite the save that was loaded" (AGENTS.md section 9, `SaveFile.write/3`). The new rule: saving into a filled slot asks first, in the page (never `window.confirm`, AGENTS.md section 8).
- **A backup before overwriting: yes.** Replacing a filled slot first writes the old bytes to `SAVEn.GAM.mirror-backup` (the game ignores that name), so an overwrite is never final.
- **A plain "unsaved changes" badge** in the top bar, so a wizard edit is clearly not saved until the user saves.
- The top bar is **page-wide** (map, wizard pages, Lab), not part of the map header.

## How it works

The browser holds the folder handle and reads and writes the files; the server never sees the user's disk, so this works the same from Docker. Load: the page reads `SAVEn.GAM` and sends its bytes to the
server's session (about 123 KB). Save: the server builds the file's bytes and sends them to the page, which writes them into the chosen slot. The server keeps the save and its edit history in memory as it does now; only where the bytes come from and go to changes.

## What was built (2026-10-16)

First try: a thin bar above every page. Kevin tried it and it was confusing (tiny, easy to miss, a second load bar still on the map page, no slots after choosing a folder), so he drew the layout below on paper (the two sketches are not kept in the repo) and it was rebuilt to match.

**The start page** (`/`, `MirrorWeb.LandingLive`): "Welcome to Mirror! To get started, pick your game folder", the folder's name and a **Choose folder** button. After a folder is chosen, "Select your save:" shows slots 1 to 8 (green when a save is there, grey when empty) and slot 9 (the autosave) beside them; clicking a green slot opens it and goes on to `/arcanus`. To open a different save later, click the logo. A **Continue with SAVEn.GAM** link shows when a save is already open.

**The header** (every other page, `MirrorWeb.SaveSlots.header/1`): logo; **Arcanus / Myrror** tabs and a pill for each wizard in the save; at the right an **Unsaved changes** badge and **Save to:** with squares 1 to 8. The old site header (Overview, theme) and the map page's own plane tabs, wizard links, path box and "Save as" box are gone; Lab, Tile probe and the theme switch moved to the small row at the right of the tabs. The map page keeps its own menu row (title, Edit, Lab).

How it works: `MirrorWeb.SaveSlots` is mounted on every LiveView (`on_mount` in `MirrorWeb`), gives the socket a `:slots` assign and handles the `slots:` events, so every page shares one implementation. Its browser half is the `SaveSlots` hook (`assets/js/save_slots.js`; pure helpers in `save_slots.mjs` with Node tests). The folder handle lives in the tab (and in IndexedDB between visits), so it is there on every page. Server side: `SaveFile.from_binary/2`, `SaveManager.load_bytes/3`, `slot_bytes/1`, `mark_saved/3`, `unsaved_count/1`.

- Opening: slots 1 to 9. Saving: slots 1 to 8 only. A full slot asks first (a floating box, so nothing shifts); a failed write leaves the edits marked unsaved.
- **The old file is copied to `SAVEn.GAM.mirror-backup` once: an existing backup is kept, so it stays the save as the game wrote it** (Kevin's note said only "a backup"; keeping the first one is my choice, because overwriting it on every save would lose the original on the second save). A failed backup stops the save.
- The folder's *name* is shown, not its full path: browsers do not tell a page where a folder is.
- The path box survives only in the Lab, for browsers without the folder picker; STORY-061 deletes it (and `load_save`/`save_file`) when Kevin says so.
- The old home page ("Survey both planes…") is gone; the README says what Mirror does.

**Checked:** server tests (`save_slots_test.exs`, `save_manager_test.exs`), Node tests, and in the in-app browser against a **fake** folder (a stand-in object for `showDirectoryPicker`, backed by a real save): the start page, slots, opening one, the header on the map and a wizard page, the slots staying across page changes, Save to an empty slot, Replace with the backup made. **Not checked:** the real Chrome folder picker and its permission prompts (Kevin's first try found the folder did not show slots: *cause not found*, the fake folder works; first suspect is the real picker's handle or a folder Chrome refuses), the remembered folder after a restart, and a save written this way loading in DOSBox ([real-game-acceptance.md](../reference/real-game-acceptance.md)).

## Open questions

- **Remembering the folder.** The browser can keep the folder handle between visits (IndexedDB), but Chrome asks the user to re-allow access each visit (one click). *Guess:* acceptable.
- **Slot labels.** *Guess:* a save carries its own name or turn number that could label the buttons on hover; not checked. Plain slot numbers are enough for the first version.
- **What happens to the save-path logic on the server** (`state.save_path`, "Save as" suggestions, the overwrite refusal): it is replaced or removed. Tests that cover it change with it.
- **A saved game opened by the game while Mirror has it open:** the slot buttons should refresh when the page regains focus.

## Stories

- [STORY-058](../stories/STORY-058-top-bar-and-unsaved-badge.md): the page-wide top bar and the unsaved-changes badge
- [STORY-059](../stories/STORY-059-pick-folder-and-load-slot.md): pick the game folder, show the slots, load a slot
- [STORY-060](../stories/STORY-060-save-to-slot.md): save to a slot, with an overwrite warning
- [STORY-061](../stories/STORY-061-retire-the-path-box.md): retire the path box and the old save-path rules

Order: 058, then 059, then 060, then 061. Separate from this epic: [STORY-062](../stories/STORY-062-fix-the-toasts.md), the toast messages (a save's "Saved" message is one of them).
