# STORY-016: Edit mode shell

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** open, after STORY-015
**Size:** medium

## What to do

- **Edit toggle** in the header. `Esc` exits. The URL reflects it
  (`?edit=terrain`) so a refresh keeps the mode.
- **Pick what to edit**: Terrain | Roads & specials | Structures | Units.
  Only that layer responds to clicks, and only its tools show. This
  replaces MMS-style key chords with explicit selection.
- **Mouse model**: left = apply the current tool; right = pick or sample
  (eyedropper). Modifiers are optional shortcuts only, and each tool
  documents them inline.
- **Undo/redo** (the server-side stroke history already exists) and a
  visible **unsaved changes** marker.
- **Save as…** writes a new `.GAM` (defaulting to a new name, never the
  loaded file). `SaveFile.write` already keeps a backup.
- Nothing is sent to the server in View mode except loads.

## Definition of done

- You can enter Edit, pick Terrain, change a tile with the (for now) raw
  tool, undo it, redo it, and **Save as** a new file. The original is
  untouched.
