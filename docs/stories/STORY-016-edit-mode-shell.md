# STORY-016: Edit mode shell

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** done 2026-09-23. `✎ Edit` / `Done` in the map header (and `Esc`)
toggle `?edit=terrain`. The toolbar has a layer picker (Terrain live; Roads,
Structures and Units shown disabled), a tile brush with a preview from the
atlas, Undo/Redo, an "N tiles changed" counter with **Discard**, and
**Save as** (suggests the next free `SAVEn.GAM`; refuses the loaded file).
Input: left paints, right picks; wheel still zooms; space-drag or
middle-drag pans. View mode is unchanged (hover only). Covered by
`test/mirror_web/live/map_live_edit_test.exs` (needs game files).
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
