# EPIC-001: Correct terrain tile rendering (rotation/layering)

**Status:** done on the MOMIME-PNG path (PR #3 + PR #4 — rotation/smoothing verified against MOMIME's real rule data). **Superseded 2026-09-22** by the discovery that save terrain values are `TERRAIN.LBX` tile numbers — see [../reference/classic-terrain-format.md](../reference/classic-terrain-format.md). The classic-art path needs none of this epic's smoothing machinery; the in-app switch is tracked under [EPIC-002](EPIC-002-remove-momime-dependency.md).
**Owner:** [Kevin](https://github.com/KevinAsbury)

## Goal

Load a Master of Magic save file and render the overland map on canvas, using the
game's own LBX tile assets, with correct terrain, correct shoreline/rotation
variants, and both planes (Arcanus/Myrror).

## Where it stands

Historical record of how the MOMIME-PNG rendering path got fixed. Kept
because the investigation (and `Mirror.Quality.SmoothingRules`) is correct
and may still matter if Mirror ever *edits* terrain — but for drawing a
save, see [../reference/classic-terrain-format.md](../reference/classic-terrain-format.md).

## Update 2026-09-22: found the real algorithm + got a working dev setup

Full writeup: [../notes/2026-09-22-momime-source-findings.md](../notes/2026-09-22-momime-source-findings.md).

Short version: pulled the actual MOMIME Java source (it's on SourceForge, not
GitHub — `git clone https://git.code.sf.net/p/momime/momime`) and found
`TileSetBitmaskGeneratorImpl.generateOverlandMapBitmask`, the real client code
that computes a tile's rotation bitmask. Mirror's version has the bit polarity
**inverted** (`0`/`1` meaning swapped), treats it as land/water when the real
game treats it as same-type-vs-different-type-as-the-center-tile, and applies
the ternary `0`/`1`/`2` values to the wrong directions (assumed diagonal-only;
real rule is uniform-across-all-8-directions and means "river," not "diagonal
edge"). The "no exact mask, what's the nearest one" fallback in
`shore_mask.ex` is also reinventing something the real game does via a
declarative rule table (`SmoothingSystemEx`) loaded from data, not a generic
cost search.

Also: Kevin found and uploaded `MAGIC.zip` (the real DOS install + 3 save
games) to Google Drive. It's extracted at `~/.mirror_assets/MAGIC` now, and
[scripts/dev_server.sh](../../scripts/dev_server.sh) runs the app pointed at it with save-file
layer offsets pulled from the [Master of Magic Wiki](https://masterofmagic.fandom.com/wiki/Save_Game_Format)
(community-reversed, but they match Mirror's own assumed layer sizes exactly
and produced a coherent, recognizable map when tested against `SAVE1.GAM`).

## What's left

Nothing on this epic. Items 1–3 of the original list (bit polarity,
same-type semantics, real `smoothingReduction` rules) landed in PR #3/#4;
item 4 (actual tile art) landed via MOMIME PNGs and is now being replaced
by direct `TERRAIN.LBX` rendering (EPIC-002).

## Stories

- [STORY-001](../stories/STORY-001-jagged-shorelines.md) — closed (obsolete on the `TERRAIN.LBX` path)
