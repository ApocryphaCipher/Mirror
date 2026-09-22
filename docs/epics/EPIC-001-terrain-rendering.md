# EPIC-001: Correct terrain tile rendering (rotation/layering)

**Status:** unblocked — real assets + real algorithm in hand, ready to implement
**Owner:** Kevin

## Goal

Load a Master of Magic save file and render the overland map on canvas, using the
game's own LBX tile assets, with correct terrain, correct shoreline/rotation
variants, and both planes (Arcanus/Myrror).

## Where it stands

Ocean and land base tiles render, on both planes, on canvas. Shoreline/edge tile
**rotation is wrong** — the game picks a specific edge/corner/coast tile variant
per-tile based on its 8 neighbors, and Mirror isn't selecting the right variant
consistently.

Prior attempt (~7 months ago, via Gemini) got partway there but never nailed the
neighbor-mask → correct-tile mapping. See [../notes/2026-09-22-repo-recon.md](../notes/2026-09-22-repo-recon.md)
for what's actually in the code today.

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

1. Fix `Mirror.Map.adj_mask/3` bit polarity + same-type semantics (not
   land/water).
2. Fix the ternary/river handling in `shore_mask_digits/3` to match the real
   per-direction river logic instead of assuming diagonals.
3. Check whether Kevin's MOMIME `resources/` dump includes the graphics XML
   (not just the flattened `resources-map.txt`) — if so, parse the real
   `smoothingReduction` rules instead of keeping the cost-search fallback.
4. Get actual tile art rendering (LBX tagging via the Tile Bit Inspector, or
   wire up MOMIME PNG resources) so rotation fixes are visually checkable.

## Stories

- (none carved out yet — this is still small enough to do as one pass through
  `map.ex` + `shore_mask.ex` + their JS mirror in `map_hooks.js`)
