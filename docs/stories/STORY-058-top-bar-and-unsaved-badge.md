# STORY-058: A page-wide top bar and an unsaved-changes badge

**Parent:** [EPIC-012](../epics/EPIC-012-open-and-save-from-the-browser.md)
**Status:** open (2026-10-15)
**Size:** small to medium
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-15

## What to do

Move the load and save controls out of the map header into one bar at the top of every page (map, wizard pages, Lab), under the site header. For now it keeps the current
controls (path box, Load, Save as) and adds:

- the **name of the loaded save**;
- an **"Unsaved changes"** badge whenever the session has edits not saved, on every page (today only the map shows an unsaved notice, STORY-026);
- **Undo and Redo** if they fit (they are global to the session).

Per AGENTS.md section 8 the bar is part of the page layout and must not change size when it shows or hides things above the map (a toolbar or notice that shifts the map moves tiles under the pointer): the badge appears in a fixed spot.

## Definition of done

- Every page shows the bar; the map header no longer carries load and save.
- A wizard edit makes the badge appear; Save as clears it.
- LiveView tests for the bar on the map and a wizard page; a check in the browser that the map does not shift when the badge appears.
