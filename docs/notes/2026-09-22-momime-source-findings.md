# 2026-09-22 (cont'd) — Found the real algorithm, and a working local setup

Two things happened this session that unblock EPIC-001:

1. Kevin uploaded `MAGIC.zip` (the actual DOS Master of Magic install, LBX
   files + `Magic.exe` + three real save games) to his Google Drive. Pulled
   it down and extracted to `~/.mirror_assets/MAGIC` (outside the repo,
   not gitignored-and-forgotten — it just lives on disk, not tracked).
2. Went and got the ground-truth MOMIME Java source instead of guessing.

## Where the real source lives

MOMIME isn't on GitHub — it's on SourceForge as a git repo:

```bash
git clone https://git.code.sf.net/p/momime/momime   # main game (728MB, has graphics/sound)
git clone https://git.code.sf.net/p/momime/map       # small com.ndg.map coordinate library
```

Copied the four files that actually matter into
[../reference/momime-source/](../reference/momime-source/) so we don't have to
re-clone 728MB every time. See that folder's README for what each one is.

## The real rotation algorithm (this is the answer to "which layer")

`TileSetBitmaskGeneratorImpl.generateOverlandMapBitmask` (Client module) is
the actual client code that computes a tile's bitmask before rendering.
Key facts, all confirmed straight from source:

- **Bit meaning is inverted from what Mirror assumes.** For each of the 8
  directions: `0` = the neighbor is the **same** tile type as this tile (or
  matches its secondary/tertiary type — tile types can group, e.g. multiple
  grass variants), `1` = **different**. Mirror's `Mirror.Map.adj_mask/3`
  ([lib/mirror/map.ex:98](../../lib/mirror/map.ex)) sets the bit to `1` when the neighbor
  *matches* — the opposite convention. Mirror's `computed_adj_mask` debug
  layer is quietly encoding the inverse of what the real game does.
- **It's not land/water, it's "same type as me."** Each tile type does its
  own smoothing pass relative to itself (with up to 2 alternate acceptable
  types via `secondaryTileTypeID`/`tertiaryTileTypeID`), not a generic
  ocean-vs-land binary. `Mirror.Quality.ShoreMask` currently generalizes to
  water-vs-land only, which is a reasonable approximation for coastline but
  wrong in general (forest-in-grass, hills-in-mountains, etc. would need the
  same treatment and don't get it).
- **The ternary value (0/1/2) is about rivers, not diagonals.** Mirror's
  `shore_mask_digits/3` assumes cardinals are binary and only diagonals can
  be `2` — that's not a real rule anywhere in the source. In MOMIME, *every*
  direction can be `0`/`1`/`2` uniformly, and `2` specifically means "a
  river runs off this tile in this direction," decided by the tile's own
  `riverDirections` data, not by neighbor inspection at all, and not
  specific to diagonal position.
- **Direction order**: N=1, NE=2, E=3, SE=4, S=5, SW=6, W=7, NW=8 (1-indexed
  string position). Matches Mirror's existing `@dirs` order, just 0- vs
  1-indexed — this part was already right.
- **The "no exact mask" fallback isn't a heuristic search — it's data.**
  `SmoothingSystemEx` holds a declarative rule table
  (`smoothingReduction`: "if N out of {these directions} equal {these
  values}, then set direction X to value Y") loaded from the graphics XML,
  applied deterministically to every possible raw bitmask up front. Mirror's
  `shore_semantic_fallbacks`/`shore_mask_fallback_cost` in
  [shore_mask.ex](../../lib/mirror/quality/shore_mask.ex) reinvents this as a generic
  cost-minimization search — which will sometimes land on a plausible-looking
  but *wrong* tile, because it isn't using the game's actual rules. If the
  `resources/` MOMIME client graphics dump Kevin has includes the graphics
  XML (not just PNGs + `resources-map.txt`), we should parse the real
  `smoothingReduction` rules directly instead of the cost search.

## Working dev setup (new)

- `~/.mirror_assets/MAGIC` — extracted DOS install (LBX files + `SAVE1.GAM`,
  `SAVE2.GAM`, `SAVE9.GAM`, `TEMPLATE.GAM`). Not in the repo, not gitignored
  reference either — just lives on disk. **Contains copyrighted game
  assets, do not commit any of it.**
- Save-file layer offsets: nobody had these written down anywhere in the
  repo (they're env vars with no defaults). Found them on the
  [Master of Magic Wiki's Save Game Format page](https://masterofmagic.fandom.com/wiki/Save_Game_Format)
  (community reverse-engineering, "research required" tag but the map
  section is solid) and they match Mirror's own per-layer byte-size
  assumptions in [save_file/blocks.ex](../../lib/mirror/save_file/blocks.ex) exactly:

  | Layer | Offset | Per-plane size | Matches Mirror's `@layer_sizes`? |
  | --- | --- | --- | --- |
  | terrain | `0x002698` | 4800 (u16 × 2400 tiles) | yes |
  | landmass | `0x004d98` | 2400 (u8 × 2400) | yes |
  | minerals | `0x013554` | 2400 | yes |
  | exploration | `0x014814` | 2400 | yes |
  | terrain_flags | `0x01cbb8` | 2400 | yes |

  File length checks out too: wiki says EOF at `0x01e1a4` = 123,300 bytes,
  which matches the real `SAVE1.GAM` size exactly.
- [scripts/dev_server.sh](../../scripts/dev_server.sh) — wraps `mix phx.server` with all the
  env vars above set (`MIRROR_MOM_PATH` + the 5 offset vars). Run it instead
  of bare `mix phx.server` to get a working dev server.
  `.claude/launch.json` points the `run` skill / browser preview at it.
- **Verified working**: loaded `SAVE1.GAM` at `/arcanus`, turned on the
  "Kinds" debug overlay (shows terrain classification as text labels
  instead of raw tile art) — got a coherent, recognizable continent/ocean
  layout with sensible `ocean`/`shore`/`grass`/`forest`/`mountain`/`tundra`/
  `desert`/`hill`/`swamp` labels and a `shore` ring around coastlines. This
  confirms the offsets, the u16 terrain read, and the base terrain-kind
  classification are all correct. **Actual tile art still doesn't render**
  — that's separate (no `priv/asset_map/terrain_tiles.json` tagging done
  yet, no MOMIME graphics resources present) — this only validates the data
  layer, not image selection.

## Why it went in circles (confirmed from the actual Codex history)

Kevin found and uploaded `Mirror Docs.zip` — 14 markdown files from
`ai/Implemented_Mirror_Codex_*.md`, one per Codex session, now copied to
[../reference/codex-notes/](../reference/codex-notes/). These are the actual prompts/plans from
the prior attempts, and they lay out the whole arc:

1. **`Fix_Grassland_And_Coast_Rotation.md`**: first real diagnosis. Treated
   the problem as "bit order is rotated 90°/180°/270° from MOMIME's" and
   proposed trying all 4 rotations at lookup time until one matches a real
   file — i.e. exactly the fallback-search pattern that ended up in
   `shore_mask.ex`/`map_hooks.js` today.
2. **`Shoreline_Adjacency_Canonicalization.md`**: escalated the theory —
   decided diagonals are ternary (`0`/`1`/`2`) where `2` means "diagonal
   land unsupported by its two adjacent cardinals" (a corner-support rule),
   cardinals stay binary land/water. This is a **self-consistent but
   invented rule** — never checked against MOMIME source, just pattern-matched
   from filenames containing `2`.
3. **`Shoreline_Semantic_Classifier.md`**: found that rule produced "toothy"
   coastlines, so added a whole semantic classifier (`straight_edge`,
   `convex_corner`, `concave_inlet`, `peninsula`, `island_tip`, `channel` —
   these exact names are in `shore_mask.ex` today) to gate *when* the
   ternary-reduction fallback was allowed to fire, to stop it collapsing
   visually-distinct shorelines into the same wrong tile.

**The actual bug**: step 2's foundational rule is wrong. Real MOMIME
(`TileSetBitmaskGeneratorImpl`, see above) uses ternary values on **all 8
directions**, not diagonals-only, and `2` means "a river exits this tile in
this direction" — it has nothing to do with corner support. Every layer
built on top (canonicalization, semantic classification, cost-based
fallback) is refining a heuristic standing on a made-up premise. No amount
of iterating on it converges on the real game's tile selection, because
it's solving a different (self-invented) problem that happens to look
similar. That's the "going in circles" — each fix made the *symptom*
(toothy edges, missing tiles) less bad without ever being able to reach
zero, because the underlying model was never going to match.

This also means: the fix isn't "patch `shore_mask.ex` again" — it's
replace its core mask computation with the real algorithm
(same-type-as-center, secondary/tertiary type grouping, river-driven
ternary across all directions) and lean on `SmoothingSystemEx`'s
declarative reduction rules instead of the invented semantic-classifier
fallback.

## Next steps (concrete now, not speculative)

> **Update, later the same day:** all four done (PR #3/#4), then made moot
> for rendering by
> [../reference/classic-terrain-format.md](../reference/classic-terrain-format.md). The save stores
> finished tile numbers, so none of this is needed to draw a map.

1. Fix `Mirror.Map.adj_mask/3` bit polarity (currently inverted vs. the real
   game).
2. Rewrite the bitmask computation to match
   `generateOverlandMapBitmask` exactly: same-type-as-center (+ secondary/
   tertiary type IDs) per direction, river directions producing `2`
   uniformly across all 8 directions rather than diagonal-only.
3. Check whether Kevin's `resources/` MOMIME dump has the graphics XML with
   real `smoothingReduction` rules; if so, parse and use those instead of
   the cost-search fallback in `shore_mask.ex`.
4. Once art can render (LBX tagging or MOMIME PNGs wired up), re-check
   rotation visually against a known save.
