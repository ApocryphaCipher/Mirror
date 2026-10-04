# STORY-017: Terrain editing with auto-tiling

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** open. Phase 1 (core lookup and resolve engine, item 1 below)
is done, and item 2 is closed: the polar-edge gap and the sparkle-ocean
mismatches are explained (live checks, 2026-09-28 and 2026-10-04). Phase 2
has started and the **Paint type tool works in the page** (2026-10-05): a
terrain dropdown (water and seven land types), brush 1×1 / 3×3 / 5×5, fill, a
right-click eyedropper, and a status line that says what was left alone;
neighbouring tiles re-tile as you paint, the landmass layer is kept in step, and a
drag is one undo step (`Mirror.TerrainPaint`, `Mirror.Landmass`,
`Editor.paint_type/5`, `MirrorWeb.PaintTool`). Still open: the stamp / eyedrop-tile
tool, smoothing of impossible coastlines, and painting rivers, lakes, nodes and
volcanoes (item 4 is handled by exclusion: they are not painted). Not checked yet:
that the real game accepts a save with a repainted landmass layer.
**Size:** large

## Why this is the interesting one

A save stores a finished **tile number**, not a terrain type (see
[../reference/classic-terrain-format.md](../reference/classic-terrain-format.md)). Painting "ocean" onto a tile
means choosing the right ocean *and* re-choosing the right shore picture for
every neighbour. That's the "hundreds of shore tiles" problem MMS users
fought by hand.

The original game has the answer on disk: `TERRTYPE.LBX` is its
neighbour-mask → tile table (with rotation flags). We have bypassed binary decoding of this file by porting the `TERRTYPE` equivalent from the [kazzmir/master-of-magic](https://github.com/kazzmir/master-of-magic) remake, which maps an 8-way neighbour signature to a specific tile index.

## What to do

1. ~~**Tile number → terrain type**: derive from `TERRAIN.LBX` ranges (and
   check with the minimap colour table, entry 2). Document it.~~ (Done: Built `Mirror.TerrainType` to resolve tile types cleanly based on ported kazzmir table).
2. **Decode `TERRTYPE.LBX` fully** and reproduce the game's choice: for any
   existing save, recomputing each tile from its type + neighbours should
   give back the tile number already stored (or explain the exceptions,
   e.g. random variants). That's the correctness test. **Done for the
   polar-edge question:** ported kazzmir's table and resolve algorithm
   (`Mirror.TerrainType`); the correctness test on `SAVE1.GAM` originally
   gave a 92.18% match rate with ~375 unexplained mismatches concentrated
   at the map's north/south edges. Checked live against a running game via
   the DOSBox Staging memory API (2026-09-28, see
   `docs/reference/live-ram-map.md`): kazzmir's off-map default
   (`:ocean` for a neighbour past row 0/39) was wrong — leaving that
   direction unconstrained instead resolves every edge tile on both
   planes, including the (0,0) corner. Fixed in
   `test/mirror/terrain_type_test.exs`'s `build_region`; unexplained
   mismatches dropped to 195, none on the edge rows. The remaining 195 are
   interior ocean tiles stored as tile 601, the animated "sparkle" ocean
   (4 frames, the only animated ocean tile), which the game scatters at
   random, about 1 tile in 5, with no neighbour rule. Checked live on
   three fresh worlds on 2026-10-04; see `docs/reference/classic-terrain-format.md`'s
   `TERRTYPE.LBX` section. Item 2 is closed. For painting, ocean is tile 0,
   or 601 about 20% of the time.
3. **Tools** (*Paint type* done, see the status above; the raw *Paint tile* box
   now has a quick pick of plain tiles; *Cycle* was already there; *Stamp
   exact tile* and an eyedrop-tile are still open):
   - *Paint type* (brush / fill): set types, then re-resolve the painted
     tiles and their 8 neighbours. **Keep a neighbour's existing tile if it
     still matches** (the game does; checked on a live Raise Volcano, 6 of 6,
     and a Change Terrain, 4 of 4, changed neighbours identical to the
     resolver's pick, see
     `docs/reference/classic-terrain-format.md`).
     **Done:** `TerrainType.matches?` now treats sparkle-ocean 601 like tile 0
     (the game places 601 over any ocean, even beside shore: 513 of 1,213
     live 601 tiles have a non-ocean neighbour), so the keep-if-valid rule
     no longer swaps valid 601 neighbours for tile 0. `resolve_tile/2` still
     returns 0 for ocean; using 601 for ~20% of painted ocean is cosmetic.
   - *Cycle picture* (MMS "L/R"): step through variants of the same type
     without changing the type.
   - *Stamp exact tile*: pick from a tile palette, or eyedrop any tile on
     either plane (MMS "Alt-F3/F4") and stamp it verbatim.
4. Rivers and node/volcano tiles: **excluded for now.** `TerrainPaint`
   never paints or changes rivers, lakes, nodes or volcanoes in the brush
   (reported as `skipped`), because their tiles have rules tied to each other.
   Painting beside them often leaves a tile that cannot be fixed (52% of
   paints that touch one), so supporting them properly is future work.

## Continents (landmass layer)

Type painting changes land ↔ water constantly, so it must also maintain
the save's **landmass** IDs (`0x004d98`). **The rule is decoded** (2026-10-04,
see `docs/reference/classic-terrain-format.md`, "Landmass layer"):
`Mirror.Landmass` implements it, with `violations/2` (for the STORY-029 edit
checker) and `repair/2` (keeps IDs stable, only renumbers what an edit
changed). **Still to do:** call `Landmass.repair/2` from the paint tool (and
from cycle) whenever an edit can change land/water or join/split a landmass.
Don't ship type painting that writes terrain without it.

## Definition of done

- Recomputing `SAVE1.GAM` from types reproduces its stored tiles (with
  documented exceptions).
- Painting ocean into a landmass produces a clean coastline with no manual
  shore work.
