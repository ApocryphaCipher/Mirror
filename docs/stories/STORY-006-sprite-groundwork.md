# STORY-006: Sprite groundwork: full GOG install + named-sprite catalog

**Parent:** [EPIC-004](../epics/EPIC-004-overland-map-features.md), shared with [EPIC-005](../epics/EPIC-005-animated-terrain-and-magic.md)
**Status:** done 2026-09-23. Catalog: [../reference/overland-sprites-and-save-blocks.md](../reference/overland-sprites-and-save-blocks.md#sprite-catalog-verified-2026-09-23-story-006).
**Size:** small–medium

## Why

Every overlay (cities, sites, units, plaques, auras, roads) comes from
`MAPBACK.LBX` / `UNITS1.LBX` / `UNITS2.LBX`. None of those are in the
local `MAGIC` install; only the GOG release has them. We also need a quick
way to see *which* entry is *what* before wiring anything.

## What to do

1. **Pull the full GOG LBX set** from Drive into `~/.mirror_assets/GOG` and
   make it `MIRROR_MOM_PATH` in `scripts/dev_server.sh`. Copy the `SAVE*.GAM`
   files over, or keep loading saves from `MAGIC` by path.
2. **Read LBX name tables** in `Mirror.LBX` (file offset `0x200`, 32-byte
   rows, e.g. `SITES` / `blue`). Show them in `/tile-probe` next to each
   entry.
3. **Force the `FONTS.LBX` entry-2 palette** for these files in
   `/tile-probe` (and check whether that also fixes the old `:auto`
   "colored noise" palette bug). Confirm index 0 decodes as transparent.
4. **Write the catalog down**: a table in [../reference/overland-sprites-and-save-blocks.md](../reference/overland-sprites-and-save-blocks.md) mapping the entries we
   need (city sizes, each site type, plaque colours, aura frames, road
   directions) to `FILE.LBX #entry[/frame]`.

## Definition of done

- `/tile-probe` shows `MAPBACK.LBX` and `UNITS1.LBX` entries with names and
  correct colours.
- The catalog table exists and later stories reference it instead of
  guessing entry numbers.

## Outcome (2026-09-23)

- 61 of the GOG LBX files are in `~/.mirror_assets/GOG`, with the saves
  copied alongside, and `scripts/dev_server.sh` points `MIRROR_MOM_PATH`
  there. Not pulled: ~36 small files (< 75 KB: `CMB*` combat terrain,
  `ITEM*`, `SPELLS`, `SPECIAL/2`, `VORTEX`, `PORTRAIT`, `HIRE`, etc.). The
  Drive connector returns those inline rather than to disk, and none of
  them are overland art.
- `Mirror.LBX` reads the name table (`names/1`, and `entries/1` carries
  `name`/`description`), decodes the real image format, and defaults to
  the `FONTS.LBX` #2 palette with index 0 transparent (alpha 0).
- The `:auto` "colored noise" bug was the **decoder**, not the palette. The
  write-up is in the reference doc. Forcing the palette alone did not fix
  it; fixing the header and frame parsing did.
- `/tile-probe` shows names, uses the game palette by default ("Grayscale"
  and "Borrow" remain), draws transparency on a checkerboard, and counts
  index-0 pixels.
- Also fixed: the entry-offset parser was off by one for files whose bytes
  4–7 are zero (e.g. MAPBACK), and RGBA was written as BGRA.
