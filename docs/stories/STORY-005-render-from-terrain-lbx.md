# STORY-005: Render the map from `TERRAIN.LBX` in the app

**Parent:** [../epics/EPIC-002-remove-momime-dependency.md](../epics/EPIC-002-remove-momime-dependency.md)
**Status:** implemented 2026-09-22 (this PR). `Mirror.TerrainLbx` plus a
`terrain_lbx` tile backend, which is the default when `TERRAIN.LBX` is in
`MIRROR_MOM_PATH`. Verified: both planes of `SAVE1.GAM` in the browser
match the reference decode exactly. A per-tile hash of every map cell
agrees on all 4800 tiles.
**Size:** medium. The format is fully known and a working reference exists
([scripts/mom_map_render.py](../../scripts/mom_map_render.py)).
**Absorbs:** STORY-002 (full-`u16` read, heuristic removal)

## What to do

1. **Decode** `TERRAIN.LBX` (entry 0 tile records, entry 1 pointers, entry 2
   minimap colours) and the `FONTS.LBX` entry-2 palette in Elixir. Format:
   [../reference/classic-terrain-format.md](../reference/classic-terrain-format.md).
2. **Build an atlas** per plane (762 tiles + extra frames for the 79
   animated pointers) once at load, and push it to the client as a sprite
   sheet plus a value → atlas-index table.
3. **Read terrain as full `u16`** everywhere (`Mirror.Map`, `map_hooks.js`),
   and delete `detectTerrainBaseSource` and related code.
4. **Draw** `atlas[plane][value]` per tile in `map_hooks.js`, behind a
   toggle next to the existing MOMIME path.
5. **Point `MIRROR_MOM_PATH` at a full install** (GOG). Update
   `scripts/dev_server.sh` and the README quick start.

## Definition of done

- `/arcanus` and `/myrror` for `SAVE1.GAM` match `mom_map_render.py`'s
  output pixel for pixel at 1×. A diff is cheap: render both and compare.
- `mix test` is green, with a decoder test (for example, value `0` → a
  20×18 ocean record) tagged to skip when game files are absent. Game
  files can't be committed as fixtures.
- A follow-up PR removes the MOMIME path after Kevin has looked at it.

## As built (2026-09-22)

- **Backend choice** (removed in STORY-014; `terrain_lbx` is now the only backend): `MIRROR_TILE_BACKEND` = `auto` (default) |
  `terrain_lbx` | `momime`. `auto` uses `TERRAIN.LBX` when found, otherwise
  MOMIME PNGs, otherwise the tagged-LBX fallback.
- **Payload:** only the referenced records (1761), as indexed pixels plus
  the palette, about 860 KB of JSON once per page. The client builds one
  atlas canvas.
- **Overlays:** the feature and embedded-special overlays are skipped on this
  backend. They reinterpret bits of the terrain value, which is now known
  to be a plain tile number.
- **Water animation:** animated tiles use `phaseIndex % 4` when a phase is
  active (snapshot/phase-loop rendering). The live view shows frame 0.
- **Not done here (deliberately):**
  - `detectTerrainBaseSource` and the low-byte kind tables are left in
    place. They only feed the MOMIME path and the debug overlays, and go
    away with it in the removal PR.
  - Tiles are drawn stretched into the canvas's square cells (20×18 → N×N),
    the same as the MOMIME path. Native 20×18 cells would mean changing the
    canvas geometry, which is a separate change.
- **Dev setup:** `~/.mirror_assets/MAGIC` got the GOG `TERRAIN.LBX` copied
  in. Its `Fonts.lbx` is byte-identical to GOG's.
