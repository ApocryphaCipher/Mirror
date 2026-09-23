# 2026-09-22 — First-look recon

Repo: `ApocryphaCipher/Mirror` (note: not "ApocraphaCypher" — org name is
`ApocryphaCipher`, `y`→`y` but "Cypher"→"Cipher"). Cloned to
`~/repo/elixir/Mirror`.

## Stack / state

- Phoenix/LiveView (Elixir 1.20, OTP 29). Compiles clean (only harmless
  deprecation warnings — pin operator in bitstring matches, guard range step
  in `lib/mirror/map.ex`). `mix test` → 17 passed, 4 excluded
  (`discovery: true` tag), 0 failures.
- Two big files carry most of the rendering logic:
  [lib/mirror_web/live/map_live.ex](../../lib/mirror_web/live/map_live.ex) (~2600 lines, server side)
  [assets/js/map_hooks.js](../../assets/js/map_hooks.js) (~2700 lines, canvas draw + client-side mask logic)
- No local game assets in this checkout — both are required and both are
  gitignored (`/resources`, `/momime` in `.gitignore`):
  - `MIRROR_MOM_PATH` — the actual MOM install, `.LBX` files
  - `MIRROR_MOMIME_RES_PATH` — extracted PNGs from the MOMIME Java project
    (defaults to `./resources` if unset)
  - Neither exists here, so `TileAtlas.build/1` currently has nothing to load.
    Can't visually verify anything until Kevin hands over paths + a save file.

## The two rendering paths

`Mirror.TileAtlas.build/1` tries `MomimePngIndex.load_assets/0` first; only
falls back to the raw-LBX `AssetMap`-based path if that's unavailable.

### 1. Raw LBX ([lib/mirror/tile_atlas.ex](../../lib/mirror/tile_atlas.ex), [lib/mirror/asset_map.ex](../../lib/mirror/asset_map.ex))

Reads tiles directly from LBX via `Mirror.LBX`. Terrain/overlay tile→group
mapping comes from `priv/asset_map/{terrain,overlay}_tiles.json`
(gitignored), which is **hand-populated** through a tagging UI
([lib/mirror_web/live/tile_probe_live.ex](../../lib/mirror_web/live/tile_probe_live.ex), the "Tile Bit Inspector").
There is no automatic neighbor-mask → tile-variant logic on this path at
all — this explains why "ocean and land" work (those are simple/unrotated
lookups) but edges never got done automatically.

### 2. MOMIME PNG index (lib/mirror/momime_png_index.ex (removed in #13))

Reads `resources-map.txt` from an extracted MOMIME client graphics dump
(`terrain/<plane>/<terrain_kind>/<mask>-frame<N>.png`). This is where the
rotation logic Kevin remembers actually lives:

- The mask in the filename is **8 characters, each `0`/`1`/`2`** — one per
  neighbor direction (N, NE, E, SE, S, SW, W, NW) — not a binary bit-flag.
  Even indices (cardinals) are `0`/`1` (water/land). Odd indices
  (diagonals) are `0`/`1`/`2` — see `shore_mask_digits/3` in
  lib/mirror/quality/shore_mask.ex (removed in #13) for how Mirror currently computes
  this from the save's terrain grid.
- `Mirror.Quality.ShoreMask` (692 lines) + its JS mirror in `map_hooks.js`
  implement: mask computation, 90°-rotation search (masks are stored in one
  canonical rotation and rotated to match), and a whole cost-based
  "fallback" system for when the exact/rotated mask isn't in the asset set
  (`shore_semantic_fallbacks`, `shore_mask_fallback_cost`, etc.).
- **Suspicion, not yet verified:** the existence of such an elaborate
  fallback/cost system to find a "nearby" mask suggests the mask math
  itself doesn't reliably produce masks that exist in the real asset set —
  i.e., Gemini built a heuristic search to work around wrong masks rather
  than fixing the computation. Worth cross-checking `shore_mask_digits/3`
  against the actual MOMIME Java source before trusting the fallback layer.
  NOTICE.md cites the exact files to check:
  `momime-map/src/main/java/com/ndg/map/SquareMapDirection.java` and
  `CoordinateSystemUtilsImpl.java`.

## Open question for Kevin

Which path is "real" going forward — raw LBX (needs the neighbor→variant
logic built from scratch) or MOMIME PNG (needs the mask math fixed/verified
against source)? EPIC-001 is blocked on this plus the actual asset paths.

## Addendum: digging for "which layer drives rotation"

Kevin recalled that "one of the layers was a key player in the rotations"
but couldn't remember which. `priv/mirror_stats.dets` (checked into git,
~87KB) turned out to be a research database from real save-file analysis —
it has two dataset fingerprints from an actual 155,588-byte save loaded
2024-04-27 and again 2026-01-30, with histograms already computed. The
`Stats.set_bit_name`/`set_value_name` labeling feature exists in the code
but was never actually used (0 named entries) — whatever was learned about
individual bits lived only in the Gemini conversation, not in this file.

The five save-file layers ([lib/mirror/save_file/blocks.ex](../../lib/mirror/save_file/blocks.ex)):
`terrain` (u16), `terrain_flags` (u8), `minerals` (u8), `exploration` (u8,
fog of war), `landmass` (u8, continent id). Plus one **derived** (not
save-file) layer, `computed_adj_mask`, computed on the fly by
[lib/mirror/map.ex](../../lib/mirror/map.ex) `adj_mask/3`.

Two candidates turned up, neither confirmed:

1. **`terrain` high byte.** The u16 terrain value is split low byte =
   `terrain_base_u8` (type), high byte = `terrain_embedded_special_u8`
   ([lib/mirror/engine/session.ex:296](../../lib/mirror/engine/session.ex)). Named "embedded special" in
   code — current working theory is this is an embedded resource/special
   icon, not rotation — but nobody has actually verified what it means.
2. **`terrain_flags` (u8).** Currently coded as 8 independent per-tile
   feature bits (roads/rivers/etc, see `drawFlagOverlays` in
   [assets/js/map_hooks.js](../../assets/js/map_hooks.js)). But the DETS histogram for this layer is
   strongly bimodal — mostly `0`, a big spike at exactly `255` (899 of 4800
   tiles, consistent across both dataset loads), and otherwise mostly
   single-bit powers of two (1, 2, 4, 8). A real independent-feature-bits
   layer wouldn't put 19% of all tiles at "all 8 features present at once" —
   that shape looks more like a sentinel/padding value than 8 independent
   flags, which makes the current `drawFlagOverlays` interpretation suspect.

By contrast, `computed_adj_mask` (the mask actually driving today's base
terrain edge/rotation selection, via `adj_mask/3` in `map.ex`) has a much
more natural-looking distribution — mode at 0 with a long tail — that's
consistent with real coastline geometry. It works by strict equality of the
raw terrain-type byte between a tile and each of its 8 neighbors, which is
a different (and arguably weaker) signal than `shore_mask.ex`'s land/water
grouping.

**Not resolved — needs Kevin.** None of this proves which layer he's
remembering; it's presented as evidence to jog memory, not a conclusion.
Re-running `mix run` against the actual save with real LBX/MOMIME assets
loaded (once paths are available) would let us name bits properly using the
`Stats.set_bit_name/4` mechanism that already exists but was never used.
