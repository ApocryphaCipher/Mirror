# STORY-002: Stop the circular terrain-base-source auto-detect heuristic

**Parent:** [../epics/EPIC-003-terrain-value-classification.md](../epics/EPIC-003-terrain-value-classification.md)
**Status:** open — small, ready to start, but low value on its own
**Size:** small (~30–60 min)

## The bug

`assets/js/map_hooks.js`'s `detectTerrainBaseSource()` picks between 4 ways
of extracting a "terrain type number" from each tile's raw value (`lo`,
`hi`, `lo_nibble`, `hi_nibble`) by scoring each against
`TERRAIN_KIND_BY_BASE_ID`, a 16-entry table. `lo_nibble` can only ever
produce 16 distinct outputs, so it trivially "recognizes" 100% of them
against a 16-entry table — while the full byte (`lo`, 0–255 possible
values) correctly reports most values as unrecognized, since the table
only has 16 entries. The heuristic rewards the option that discards the
most information. Confirmed live: `lo_nibble` is what's currently active.

The Elixir side never had this problem — `Mirror.Map.terrain_type/1` and
`Mirror.Quality.ShoreMask.terrain_base_kind_for_value/1` both already use
`value &&& 0xFF` (full low byte, no nibble truncation). This bug is
JS-only, and it makes the JS client disagree with the server about what a
tile even is.

## What to do

Remove `detectTerrainBaseSource()`, `terrainBaseCandidates()`,
`sampleTerrainBaseCandidate()`, and the `terrainBaseSource`/
`terrainBaseSourceStats` state entirely. Hardcode full low-byte extraction
(`value & 0xff`) to match the Elixir side, removing the JS/Elixir
disagreement.

## Why this alone won't fix anything visible

`TERRAIN_KIND_BY_BASE_ID` is still only 16 entries and still doesn't cover
values above 15 or include river/volcano/node types. Doing this story in
isolation means going from "wrong via a disguised heuristic" to "openly
incomplete" — more `unknown`/magenta tiles, not fewer. **Do this together
with or right before STORY-003**, not as a standalone shippable change,
unless the goal is specifically to surface the gap for STORY-003's
research (which is a legitimate reason to do it first — makes the scope of
"how many tiles are actually unclassified" visible and measurable).

## Definition of done

- `detectTerrainBaseSource` and friends removed from `map_hooks.js`.
- Terrain base extraction is `value & 0xff` everywhere in JS, matching
  Elixir.
- A quick measurement (browser console, same pattern used throughout this
  investigation) of how many real tiles in `SAVE1.GAM` now fall through to
  `unknown` — this number becomes the concrete target for STORY-003.
