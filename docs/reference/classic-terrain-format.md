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
already stores the result). Only relevant if Mirror ever edits terrain.
Decoded only superficially so far.

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
