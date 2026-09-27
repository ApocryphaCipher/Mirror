# STORY-012: Units on the map with banner-colour plaques

**Parent:** [EPIC-004](../epics/EPIC-004-overland-map-features.md)
**Status:** **Done** (2026-09-26). Units decoded, stacks collapsed, city/tower garrisons hidden, and rendered with banner-colour plaques and figures.
The figure and plaque art is catalogued (STORY-006).
The unit record layout and type table are in
[kazzmir-save-layouts.md](../reference/kazzmir-save-layouts.md).
Checked on SAVE1: 42 units, and Freya's Barbarian Spearmen (39) and
Swordsmen (40) at Norport.
**Live RAM (2026-09-24):** fields and all banner colours checked; **dead units stay in the table with plane/owner `0xff`**. See [the evaluation](../notes/2026-09-24-live-ram-evaluation.md).
**Size:** medium–large

## What to do

1. **Decode** the units block: `0x00b734`, up to 1009 × 32 bytes, live
   count at `0x0009e2`. Need x/y/plane, owner, unit type at minimum.
   Verify against units you can identify in a known save (e.g. the
   starting spearmen next to each capital).
2. **Unit figure**: `UNITS1.LBX` (120) + `UNITS2.LBX` (78) `STATFIG` entries,
   18×16. Confirm the unit type → entry mapping (likely a straight index
   across both files).
3. **Plaque**: the coloured backing the figure sits on, in the owner's
   banner colour (wizard `+0x16`; neutral/rampaging monsters use the
   neutral colour). The `MAPBACK.LBX` `SITES` blue/green/purple/red/yellow/
   neutral entries are the likely source.
4. **Stacks**: one plaque + figure per tile (the real game shows the top
   unit of a stack). Units inside cities/towers are hidden, as in the game.

## Definition of done

- Every visible stack in `SAVE1.GAM` shows the right unit figure on the
  right owner-coloured plaque, on the right tile, toggleable via STORY-009.

## Outcome

- Pure module `Mirror.SaveFile.Units` (`lib/mirror/save_file/units.ex`) decodes the unit records (`0x00B734`, up to 1009 × 32 bytes, count u16 at `0x0009E2`).
- Dead units (owner or plane set to `0xFF` mid-turn sentinel) and records outside valid ranges (`x < 60`, `y < 40`, `plane in [0, 1]`, `owner in 0..5`, `type < 198`) are skipped.
- Garrison filtering: cross-references `Cities.parse/1` and `Sites.parse/1` (`:towers` list). Units on city tiles (`{x, y, plane}`) or tower tiles (`{x, y}` across both planes) are hidden from the overland map, matching original game behavior. In `SAVE1.GAM`, all 42 starting units are garrisons inside cities, so none appear on the open map on turn 1.
- Stack collapsing: `collapse_stacks/1` groups units by `{x, y, plane}` and selects the top unit with `top_of_stack/1`.
  *UNVERIFIED GUESS*: `+18` draw priority sort direction is assumed descending (higher numerical value shown on top, breaking ties by lower save-file index); this candidate field and sort direction require verification against DOSBox.
- Preloading unit figures and plaques: `Mirror.OverlaySprites.load/1` loads `@plaques` (`MAPBACK.LBX` #14..#19 for blue, green, purple, red, yellow, neutral; 20×18) and all 198 unit figures (`UNITS1.LBX` #0..#119, `UNITS2.LBX` #0..#77; 18×16, 1 frame). Preloading all 198 figures up front decodes in ~6 ms and adds ~76 KB base64 JSON to the initial sprite payload, keeping client sprite management synchronous and simple.
- Rendering: `assets/js/map_overlays.js` implements `DRAWERS.units`, drawing the pre-coloured plaque centered on the tile and the grayscale unit figure centered on top of it.
- Wired into `MapLive`: `unit_items/2` decodes visible units with owner banner colours and pushes the `"units"` layer from `push_overlays/1`.
- Tests using synthetic fixtures in `test/mirror/save_file/units_test.exs` test valid decoding, dead unit filtering (`0xFF` plane/owner), stack collapsing, city and tower hiding (towers across both planes), `figure_sprite/1` mapping (types 0, 119, 120, 197), and empty/truncated raw binaries (`[]` without crashing). Real-save tests in `units_test.exs`, `overlay_sprites_test.exs`, and `map_live_edit_test.exs` verify `SAVE1.GAM`, `MAPBACK.LBX`, `UNITS1.LBX`, and `UNITS2.LBX` integration.
