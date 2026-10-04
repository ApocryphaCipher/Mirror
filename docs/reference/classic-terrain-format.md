# Classic terrain format: save values → `TERRAIN.LBX` tiles

**Status:** implemented in the app as the `terrain_lbx` tile backend
(`Mirror.TerrainLbx`, STORY-005). Verified 2026-09-22 by rendering `SAVE1.GAM` (both planes)
end-to-end from the GOG release's `TERRAIN.LBX`, with no smoothing or
classification code at all. Output matched the real game: smooth
coastlines, rivers, mountain ranges, nodes, volcanoes, polar tundra.
Reference implementation: [scripts/mom_map_render.py](../../scripts/mom_map_render.py) (~150 lines of
Python + Pillow).

## The one-line version

**A save's terrain value is a tile number, not a terrain type.** The game
resolves edges/rotation/rivers once, at map generation, and stores the
exact tile to draw. A renderer only has to look that number up in
`TERRAIN.LBX`.

## Save file

- Terrain layer at `0x2698`: 60×40 `u16` little-endian per plane, Arcanus
  block then Myrror block, row-major (unchanged from what Mirror already
  reads — see [../notes/2026-09-22-momime-source-findings.md](../notes/2026-09-22-momime-source-findings.md)).
- Values are **full 16-bit**, range `0x000`–`0x2F9` (0–761) per plane.
  Measured on `SAVE1.GAM`: ~26–28% of tiles are `> 0xFF`, so any
  low-byte-only read (what Mirror does today, in both Elixir and JS)
  corrupts roughly a quarter of the map.

## `TERRAIN.LBX` (3 entries)

| Entry | Size | Contents |
| --- | --- | --- |
| 0 | 676,416 | Tile image records (see below) |
| 1 | 3,048 | 2 × 762 `u16` tile pointers — Arcanus values 0–761, then Myrror |
| 2 | 1,524 | 2 × 762 bytes — minimap palette index per tile value |

**Tile records**: 384 bytes each, addressed from the start of the *file*
(record *k* at file offset `k * 384` — the LBX header + entry-0 preamble
occupy exactly records 0–1). Each record: 16-byte header (`u16` width = 20,
`u16` height = 18, …), then 360 pixel bytes **column-major** (x outer,
y inner), then 8 bytes padding.

**Tile pointers** (entry 1) use EMS-style banking — 48 KB banks of 128
records:

```
w       = ptr[plane * 762 + value]
record  = ((w & 0x7F) // 3) * 128 + (w >> 8)
animated = (w & 0x80) != 0     # 4 consecutive records = 4 animation frames
```

79 of the 1524 pointers are animated (water-type tiles).

**Palette**: `FONTS.LBX` entry 2, first 768 bytes — 256 × RGB, 6-bit VGA
(scale by 255/63, as `Mirror.LBX.Palette` does). This is the palette for
every classic image, not just terrain. The earlier "colored noise" in
`Mirror.LBX` turned out to be a decoder bug, not the palette (STORY-006;
see [overland-sprites-and-save-blocks.md](overland-sprites-and-save-blocks.md#lbx-formats-as-implemented-in-mirrorlbx)).

## `TERRTYPE.LBX` — the original game's own smoothing table

One entry of `u16` lookup tables indexed by an 8-bit neighbour mask; each
value is a tile index in the low bits plus rotation/flip flags in bits
14–15 (`0x4000`/`0x8000`/`0xC000`). This is what the game uses to *pick*
tiles when generating or editing a map. A viewer never needs it (the save
already stores the result). 

**STORY-017 (Auto-tiling):** Rather than reverse-engineering `TERRTYPE.LBX`'s raw binary layout, we ported the logic directly from the BSD-licensed [kazzmir/master-of-magic](https://github.com/kazzmir/master-of-magic) remake, which maps an 8-way neighbour signature to a specific tile index. 
- Validation against `SAVE1.GAM` (4,800 tiles) yielded an exact match rate of 38.25% (later 40.35%, see below).
- Factoring in decorative valid variants (i.e. where the stored tile perfectly obeys the rules for its neighbours, but wasn't the first matching index), the total match rate was **92.18%**, with ~375 unexplained mismatches concentrated at the map's north/south edges.
- **Resolved 2026-09-28:** kazzmir's off-map default (treating a north/south neighbour past row 0/39 as `:ocean`) was wrong. Checked live against a running game via the DOSBox Staging memory API (`docs/reference/live-ram-map.md`): a fresh random map's row 0, row 39, and the (0,0) corner tile all failed to resolve under `:ocean`, but resolved correctly (exact or valid variant, 100% of edge tiles on both planes) when the off-map direction is left **unconstrained** instead — i.e. the tile simply has no rule for a direction that doesn't exist, rather than a synthetic ocean neighbour. Applying this to `test/mirror/terrain_type_test.exs`'s `build_region` against `SAVE1.GAM` cut unexplained mismatches from 375 to 195, and eliminated them entirely on the edge rows (0/60 unexplained on all four edge rows, both planes). The remaining 195 unexplained mismatches are interior ocean tiles where the game stored tile 601 and the resolver picked tile 0.
- **Resolved 2026-10-04: tile 601 is the animated "sparkle" ocean, placed at random.** Not a strict/loose rule variant (that was a guess). In the `TERRAIN.LBX` pointer table (entry 1) tile 0 is a static single frame and tile 601 is a 4-frame animation, the only animated ocean tile. Live check (DOSBox fork, three fresh New Games on different land sizes, both planes, collection `mom-live-2026-10-04`, checkpoints 56-61): **20.5% of ocean tiles (0 or 601) in rows 2-37 are 601** (1,213 of 5,925); the share is about 20% at every distance from shore and does not depend on how many neighbours are 601 (17-25% for 0-4 such neighbours), so no clustering and no neighbour rule; 42% of the 601 tiles (513 of 1,213) have a non-ocean neighbour, so kazzmir's "ocean-only on every side" rule for 601 is not how the game places it (*guess:* the generator swaps some tile-0 ocean for 601 after resolving). Tile 0's rules accept all 1,213 real 601 tiles (kazzmir's 601 rule accepts 700), so `TerrainType.matches?` now checks 601 with tile 0's rules; against `SAVE1.GAM` this cuts the unexplained mismatches from 195 to 5. The 5 left are unrelated: two at the east map edge on polar tundra (59,1) and (59,38), two coast pieces (32,17) and (46,25), and one Myrror tundra tile beside a river (34,7). **Checked by eye in the real game (2026-10-04): (46,25) is a visible flaw in the game's own SAVE1 map.** The stored shore tile 21 draws a hard-edged notch with a thin green sliver, while tile 20 (what the rules pick) draws a clean straight coast; the tile is identical in SAVE1, the edited save and the live game. So at least this mismatch is the game's own generator, not a gap in the rules. The other four were not looked at. Terrain counts were identical between turn 1 and five turns later on all three worlds, so ocean never flips between the two after generation. Rows 0, 1, 38 and 39 hold no ocean tiles (neither 0 nor 601).
- **For painting (STORY-017 phase 2):** any ocean tile accepts 0 or 601; paint 0, or 601 at about 1 in 5 to look like a generated map.

### How the game re-tiles around a change (live check, 2026-10-04)

Raise Volcano on Arcanus (8,17), desert tile 306 → 179, changed exactly 6 tiles and none on Myrror (RAM after the cast vs the save written just before; checkpoint 66). The volcano's own tile changed, plus five desert neighbours to other desert variants: (7,16), (8,16), (7,17), (7,18), (8,18). The three neighbours on the east side did not change.

Run through `Mirror.TerrainType`: in all 6 cases the old tile no longer matched its new neighbourhood and the game's new tile does, and **the new tile is exactly the one `resolve_tile/2` picks (6 of 6)**. Every unchanged neighbour still matched. The unchanged ones include tiles where the resolver would pick a different valid variant (177 → 166, 254 → 251, 184 → 163). So the game **re-picks a neighbour only when its current tile stopped being valid, and keeps it otherwise**. For painting (STORY-017 phase 2): after a type change, re-resolve the tile and its 8 neighbours, but keep any neighbour whose existing tile still `matches?`.

**Second check, Change Terrain (spell 15), same day.** Cast on Arcanus (41,15), desert tile 333 → grass tile 162 (checkpoints 67 before, 68 after). Five tiles changed, none on Myrror: the target plus four neighbours that stayed desert, (40,14) 311 → 306, (40,15) 317 → 311, (40,16) 294 → 402 and (41,16) 331 → 379. The same result as the volcano:
- All 4 neighbours had a tile that stopped matching, and the game's new tile is **exactly the resolver's pick (4 of 4)**. Every other neighbour still matched and was left alone.
- The cast tile itself: the game picked grass tile 162 and the resolver picks grass tile 1. Both are valid. Grass has several equivalent variants (1, 162, 173, 180, ...) and the game's stored choice is not always the first one, like the ocean's 0 / 601. So for the target tile, any valid variant is acceptable.
- Nothing else moved: minerals, terrain flags and the other plane were untouched.

### Animated tile numbers (STORY-007)

Entry 1 marks 42 tiles on plane 0 as animated (4 frames each) and 37 on plane 1: Myrror has no `18`, `31`-`33` or `54`. Identified 2026-10-04 by rendering each sprite from `TERRAIN.LBX` and checking where it sits in 140 maps (3 fresh worlds plus the vault's older dumps and saves):

| Tiles | What they are | Basis |
| --- | --- | --- |
| `601` | Sparkle ocean, placed at random (~20% of ocean) | See above |
| `31`, `32`, `33` | Ocean with a bright sparkle dot at a tile corner. `32` and `33` are the centre of a small enclosed pond | Sprites. `31`: ocean E, S and SE in ~83% of 202 tiles. `33` (live 2026-10-04, Arcanus x=48 y=29): N `84`, W `83`, E `85`, S `82`, all four diagonals land, so a plus-shaped pond with `82`-`85` as its four arms. `32` (two maps): N `84` and W `83` again, other sides other coast pieces, no plain ocean next to it |
| `34`-`49` | Shoreline-wave coast, convex corner, 4 groups of 4 variants (SE: 34-37, NW: 38-41, SW: 42-45, NE: 46-49) | Sprites; only the named diagonal neighbour is ocean (50-90% of tiles) |
| `54` | Narrow water channel running east-west, with land on both sides | Sprite; four tiles in three fresh maps, each with a coast-family tile to the west and east (e.g. `50` / `110`, `95` / `111`, `95` / `110`), so a run of east-west channel pieces |
| `146`-`161` | Shoreline-wave coast pieces, like `34`-`49` (curved coasts); rare in fresh maps | Frame diff (below). Which coastline shapes get these over the static coast pieces is not worked out |
| `168` | Sorcery node (blue pond) | Sprite and ~20 per plane across 3 worlds |
| `169` | Nature node (sparkling green) | Same |
| `170` | Chaos node (red crater) | Same |
| `179` | Volcano (lava crater) | **Checked live 2026-10-04:** casting Raise Volcano (spell 98) on a desert tile turned it into 179; volcanoes only come from the spell, so fresh maps never contain one (none in 140 maps) |
| `18` | Lake (a pond with a green rim) | Sprite only; never seen in 140 maps |

The ported table's `:shore` label covers coast corners, channel pieces and sparkle pieces alike, so it is too coarse to pick animation by.

**What animates (frame diff of the 4 frames, 2026-10-04).** On the coast pieces (`34`-`49`, `146`-`161`) only about 36 of 360 pixels change, and they trace the shoreline, the band where water meets land, plus a few points just offshore: a wash of waves along the edge (Kevin's reading, matched by the pixel map). On open ocean (`601`) about 22 scattered pixels change across the whole tile, the sparkle. `31` changes 4 corner pixels; `54` and `18` change 1-4 pixels. The nodes and volcano change 35-80 pixels inside the tile. So the animated cells are three kinds: shore waves, ocean sparkle, and node / volcano effects.

## Water, shore and painting a type (STORY-017)

How a painted terrain *type* turns into tiles, implemented in `Mirror.TerrainPaint`:

- **Open water is ocean or shore, and shore is the water cell next to land.** An ocean or shore cell is `:shore` exactly when at least one of its 8 neighbours is land, otherwise `:ocean`. Checked 2026-10-04 on the three fresh worlds: 5,925 ocean cells with all-water neighbours and 3,652 shore cells with a land neighbour, zero exceptions. A land cell never touches `:ocean` directly. So painting land or water changes the ocean/shore status of neighbouring open water, and only the painted cells and their 8 neighbours can change type.
- **Lakes are separate.** A lake keeps its type and is never painted or turned into ocean or shore. For the test above a lake next to open water counts as water; lakes were too rare in the data (one or two per plane) to test that case.
- **Neighbour re-picking** follows the rule from the live casts: a neighbour keeps its tile if it still matches, else it takes the resolver's pick.
- **Land types have neighbour rules too:** desert (164 tiles), tundra (163), hill (18) and mountain (17) pick edge variants by their own type among the neighbours; grass, forest and swamp have 3-5 tiles with no neighbour rules; rivers and lakes need river or water neighbours.
- **Plain grass is tile 162**, the game's own choice (Change Terrain, and 162 / 172 / 173 / 180 are the grass tiles in real maps). The resolver would pick tile 1, which no real map uses (it looks like ordinary grass).
- **Saves store tile numbers 0..761 on both planes**, so resolve with `:arcanus` for Myrror too: `resolve_tile(region, :myrror)` adds kazzmir's combined-index offset (0x2FA), which a save does not use. (The whole-save test resolves Myrror with `:myrror`, so its Myrror tiles are always counted as "valid variants", never as exact matches.)
- **Impossible coastlines.** Some land/water shapes have no shore tile: the game's table only covers the patterns its generator makes. `TerrainPaint` leaves such cells as they were and reports them as `stale`; a painted cell with no fitting tile is left unpainted and reported as `unresolved`. Smoothing the shape automatically is not done.
- **Not painted:** rivers, lakes, nodes, volcanoes and the polar rows. A cell like that in the brush is reported as `skipped` and never changed, not even beside a painted cell; if it stops matching it is reported as `stale`. One that is only a neighbour of the brush is re-tiled like any other neighbour. (Freezing those too was tried: it raised the share of paints with a stale or unresolved cell from 17.5% to 22.6%, so it was dropped.)

Checked on 1,200 random brushes (every kind, sizes 1, 3, 5) over the three worlds and `SAVE1.GAM`: painted cells always got the requested kind, the ocean/shore rule was never broken, repeating a paint never changed anything, and every newly invalid tile was one reported as `stale`.

How often a paint leaves a `stale` or `unresolved` cell (1,047 of the 1,200 paints changed something): **5.5% (43 of 776) when the brush touches no protected cell, 52% (140 of 271) when it does.** By brush size, 6 of 302 paints at size 1, 50 of 363 at size 3 and 127 of 382 at size 5. The weak spot is protected cells (rivers, lakes, nodes, polar rows): painting beside them often leaves a tile that cannot be fixed, so the editor should warn when a brush overlaps one.

## Landmass layer (save `0x4D98`, RAM `0x74DC0`)

Two planes of 2,400 bytes. Decoded 2026-10-04 from the fresh worlds, the older vault dumps and the saves: 12 distinct valid maps, 24 plane-maps. `Mirror.Landmass` implements it.

- **Land** is any tile whose type is not `:ocean`, `:shore` or `:lake`, outside the polar rows (0, 1, 38, 39). Rivers, nodes and volcanoes are land. **Everything else is ID 0** (ocean, coast, lakes and the polar tundra rows; this is most likely where the "340 land tiles with ID 0" in STORY-029's first look came from; not re-counted on SAVE1).
- **One non-zero ID per landmass.** Land tiles are in the same landmass when they touch in any of the **8** directions, x wrapping around the map and y not. With 8-way connectivity no landmass ever carried two IDs; with 4-way connectivity IDs span several regions, so diagonals count.
- **IDs are unique across both planes** (no ID appears on both Arcanus and Myrror). A single-tile island, such as a lone node, has its own ID.
- **The numbering is arbitrary** (gaps such as 1, 13, 28, 33, 34; up to about 44 on a fresh map).
- **The game does not change the layer in play.** Zero bytes changed across five turns (3 worlds), the Raise Volcano cast and the Change Terrain cast.
- The two combat checkpoints (cp29, cp30) look like violations but are not: the game reuses that memory in battle (terrain reads as garbage there), so they were excluded.

Not established (*guess*): that the polar boundary is by row rather than by tile type (every polar tile on the checked maps is tundra or coast, so both agree); what the game reads the layer for; and how the game itself would number a landmass after a land/water edit, because none of the events we caused turns land into water. For edits Mirror therefore keeps the invariant above and reuses IDs where it can (`Mirror.Landmass.repair/2`). **Live check, real game (2026-10-04):** a save painted with the Paint type tool (35 Arcanus tiles, a new 10-tile landmass with ID 2, whole map revealed) was loaded in the DOSBox fork. The game's memory was **identical to the file in all six blocks** (wizards, terrain, landmass, minerals, explored, terrain flags), so the game accepts the repainted terrain and landmass at load and does not rewrite them. The painted island was drawn correctly. Not yet observed: what a turn change does to the layer (the game left landmass alone across turns in every earlier session).

## Where the files come from

The `MAGIC.zip` install at `~/.mirror_assets/MAGIC` is **not** a complete
game — it's a CD-era hard-drive install plus third-party tools (`MTITLE71`,
`MAPEDIT7`, `CREATE30`, …) with only 23 of ~70 LBX files; `TERRAIN.LBX`,
`MAIN.LBX`, `MAPBACK.LBX`, unit art etc. were read from the CD. [Kevin](https://github.com/KevinAsbury)
uploaded the complete **GOG release** to Google Drive ("Master of Magic
Official Release" folder, plus `Master of Magic - GOG.zip`). `TERRAIN.LBX`
and `FONTS.LBX` from it are at `~/.mirror_assets/GOG`. Copyrighted — never
commit these.

## What this makes obsolete (for classic-art rendering)

- Terrain-type classification (`TERRAIN_KIND_BY_BASE_ID`, `terrain_type/1`,
  `detectTerrainBaseSource`) — not needed to draw the map at all. A
  value → kind mapping is still *useful* (debug overlays, stats), and can
  be derived from tile-number ranges or entry 2's minimap colours, but it's
  no longer on the rendering path.
- Bitmask computation + smoothing reduction (`Mirror.Quality.ShoreMask`,
  `Mirror.Quality.SmoothingRules`, the MOMIME PNG index). These are a
  faithful port of MOMIME's *regeneration* of tiles from terrain types —
  correct, but a detour when the save already names the tile.
