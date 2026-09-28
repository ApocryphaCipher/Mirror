# STORY-017: Terrain editing with auto-tiling

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** open. Phase 1 (core lookup and resolve engine, item 1 below)
is done; item 2's correctness test is at 92.18% with a genuine
unexplained gap at the polar edge (see item 2). Phase 2 (editor tools and
UI, items 3–4) remains untouched.
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
   e.g. random variants). That's the correctness test. **Partially done:**
   ported kazzmir's table and resolve algorithm
   (`Mirror.TerrainType`); the correctness test on `SAVE1.GAM` gives a
   92.18% match rate (38.25% exact index, another 53.9% a different but
   still rule-satisfying "decorative variant" tile — both count as
   explained). The remaining ~7.8% (concentrated at the map's north/polar
   edge) is **not yet explained** — see
   `docs/reference/classic-terrain-format.md`'s `TERRTYPE.LBX` section,
   marked *guess*. Don't treat this item as closed until that's resolved
   or the exception is properly documented, not just guessed at.
3. **Tools**:
   - *Paint type* (brush / fill): set types, then re-resolve the painted
     tiles and their 8 neighbours.
   - *Cycle picture* (MMS "L/R"): step through variants of the same type
     without changing the type.
   - *Stamp exact tile*: pick from a tile palette, or eyedrop any tile on
     either plane (MMS "Alt-F3/F4") and stamp it verbatim.
4. Rivers and node/volcano tiles: check how the game encodes them in
   `TERRTYPE`, and handle them or explicitly exclude them.

## Continents (landmass layer)

Type painting changes land ↔ water constantly, so it must also maintain
the save's **landmass** IDs (`0x004d98`) using the game's rule, which
isn't decoded yet (see STORY-029). Don't ship type painting that writes
terrain without updating landmass.

## Definition of done

- Recomputing `SAVE1.GAM` from types reproduces its stored tiles (with
  documented exceptions).
- Painting ocean into a landmass produces a clean coastline with no manual
  shore work.
