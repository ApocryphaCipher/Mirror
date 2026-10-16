# STORY-059: Pick the game folder, show the slots, load a slot

**Parent:** [EPIC-012](../epics/EPIC-012-open-and-save-from-the-browser.md)
**Status:** open (2026-10-15), after STORY-058
**Size:** medium
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-15

## What to do

In the top bar: a **Choose game folder** button (`showDirectoryPicker`, Chrome and Edge). Once chosen, the bar shows slots 1 to 8 as buttons, filled (green) when `SAVEn.GAM` exists in the folder, empty (grey) when not.
Clicking a filled slot reads the file in the browser and sends its bytes to the server, which loads it as today (`SaveFile.load` on bytes instead of a path). The loaded slot is highlighted.

- Remember the folder handle between visits (IndexedDB); if Chrome needs the user to re-allow access, show a single "Reconnect folder" button.
- Refresh the slot buttons when the page regains focus (the game may have saved).
- A folder with no `SAVEn.GAM` files says so plainly.
- The server side gets a load-from-bytes entry point; today's `SaveManager.load/2` takes a path.

## Definition of done

- Pure helpers for the client in `assets/js/*.mjs` with Node tests (which names count as slots, filled or empty); `mix test` for the server side (load from bytes; a bad file gives an error, never a crash).
- Checked in Chrome against a real game folder: pick the folder, see the right slots, load one, it matches what the old path box loads.
