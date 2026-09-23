# STORY-005: Render the map from `TERRAIN.LBX` in the app

**Parent:** [../epics/EPIC-002-remove-momime-dependency.md](../epics/EPIC-002-remove-momime-dependency.md)
**Status:** open, ready to start
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
