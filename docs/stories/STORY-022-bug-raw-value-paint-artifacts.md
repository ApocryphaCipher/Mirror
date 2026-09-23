# STORY-022 (bug): Stray raw-value paint shows up as map artifacts

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** open. The map pages are already protected (#13 made view mode
hover-only); **the Lab still has the footgun**.
**Size:** small–medium
**Reported by:** Kevin, 2026-09-23 (screenshot: `/lab/arcanus`, broken
shore fragments floating in the ocean near the top-left of Arcanus)

## Symptom

A strip of mismatched shore/land pieces sits in open ocean on Arcanus around
rows 6–8, columns 5–11, with nothing like it in the real game. The save file
on disk is fine. The artifacts exist only in the running session.

## What's confirmed

- **The session's terrain differs from `SAVE1.GAM`.** The SHA-256 of the
  session's Arcanus terrain block ≠ that of the file's `0x2698` block.
  Sampled differences are all the same raw value, **234**, painted over
  ocean (`0`) and one grass tile (`601`), e.g. tiles (6,7) (7,7) (8,7)
  (8,8) (9,8) (10,8). Tiles around them are unchanged.
- **The renderer is correct.** Value 234 *is* a shore-type tile number, so
  `TERRAIN.LBX` draws exactly what's stored. It's a data problem, not a
  drawing problem.
- **When:** after the STORY-005 check (~22:44 on 2026-09-22, when the
  session's terrain matched the file exactly) and before the STORY-014 check,
  in a dev server running since 17:54 that day. The session lives in ETS in
  that unnamed node, so its undo history couldn't be inspected without
  touching Kevin's session.

## Most likely cause: two silent behaviours combined

Found by reading `map_live.ex` / the old `map_hooks.js`; not yet
reproduced on purpose.

1. **The wheel changed the brush value invisibly.** The canvas captured
   every `wheel` event (`preventDefault`) and sent it to `apply_wheel`,
   which steps the active layer's *selection* value (±1, Shift ±64,
   Alt ±256). Scrolling the page with the pointer over the map, especially
   on a trackpad that fires dozens of events, walks terrain's selection from
   0 to something like 234, with no visible feedback on the map.
2. **Any left click or drag then painted it.** Left pointer-down on the
   canvas starts a paint stroke with the current selection. No armed tool,
   no confirmation.

That chain explains a single repeated odd value, placed in a small cluster.
#13 removed both from `/arcanus` and `/myrror`, but **`/lab/*` still does
both.**

## Contributing gaps

- **No "unsaved edits" signal.** Nothing tells you the session differs from
  the file. The session already keeps `original_planes`, so a diff is cheap.
- **No easy way back.** The only undo is reloading the save (which does
  reset planes and history) or clicking Undo per stroke, and neither is
  obvious.
- **Terrain values aren't validated.** `clamp_value/2` allows 0–65,535 for
  terrain, but only 0–761 are tile numbers. Anything above paints a tile
  with no art ("missing").

## What to do

1. **Reproduce** in the Lab on a fresh load: scroll over the map, click
   once, and confirm a tile gets the drifted value. Optionally, in Kevin's
   current session: Lab → Undo, and see whether the strip disappears (Redo
   restores it).
2. **Stop the wheel from changing the brush by default**: only with a
   modifier held (e.g. Ctrl/⌘+wheel), or only while a brush tool is armed.
   Plain wheel should scroll the page.
3. **Don't paint on a bare click**: require an armed paint tool (a toggle in
   the Lab's editor panel) until STORY-016's edit mode replaces this.
4. **Unsaved-edits indicator** on both the map and Lab pages: "N tiles
   changed from SAVE1.GAM" (diff against `original_planes`) with
   **Discard edits** (restore `original_planes`, clear history/redo) and a
   link to review them in the Lab.
5. **Validate terrain values** to 0–761 (`TerrainLbx.tiles_per_plane/0`) in
   `clamp_value/2`.
6. **Tests**: a LiveView test that view-mode `map_pointer` start/drag/wheel
   events leave the session untouched, and one that a Lab wheel without the
   modifier doesn't change the selection.

## Definition of done

- Scrolling and clicking around the Lab without arming a tool can't change
  the map.
- Any session that differs from its file says so, on the map page too, and
  can be discarded in one click.
- Painting terrain above 761 is impossible.

## Relation to STORY-016

STORY-016 (edit mode shell) replaces the Lab's raw painter as the real way to
edit. This ticket is the safety fix until then. Items 4 and 5 carry over into
STORY-016 as-is.
