# STORY-001: Shorelines still look jagged/toothy after the rotation fix

**Parent:** [../epics/EPIC-001-terrain-rendering.md](../epics/EPIC-001-terrain-rendering.md)
**Status:** root-caused, fix not yet implemented — the real rule table exists, see below
**Reported by:** Kevin, 2026-09-22, right after PR #3 landed

## What we know

PR #3 fixed the shore/coast bitmask computation to match MOMIME's real
algorithm (same-type-as-center, no invented ternary corner-support rule).
That fix is confirmed correct at the individual-tile level: shore masks now
resolve via exact match (not fallback) against the real MOMIME PNG resource
set, and a sampled tile (`shore/01110110.png`) showed coherent, well-composed
pixel art (a water channel with proper beach-transition pixels on both
banks) when inspected directly.

Despite that, the rendered map still looks jagged/toothy along coastlines
when viewed as a whole.

**I called this "authentic 1994 chunky art style" in the PR — that was a
premature conclusion from inspecting one tile in isolation, not from
comparing against real game reference screenshots. Kevin pushed back on
that; treat it as unverified, not settled.**

## Open questions to investigate

- Compare Mirror's rendered coastline against actual classic Master of
  Magic screenshots/video (not just individual tile art) — is this really
  how the original game's coastlines looked, or is there a real remaining
  defect?
- If it's a real defect, candidates to check:
  - Canvas rendering scale/zoom — are tiles being drawn at the wrong pixel
    size relative to how MOMIME intended them to be viewed together?
  - The rotation/canonicalization fallback chain in `resolveMomimePathForKind`
    (`resolveMomimePathForShore`) — confirm exact-match tiles are being used
    for the *majority* of shore tiles on a real map, not just the one
    sampled tile. A quick instrumentation pass (log `fallbackStep` counts
    across a full map render) would settle this fast.
  - Whether Mirror is missing river-mouth handling (ternary `2` values) —
    PR #3 explicitly doesn't implement river-driven ternary yet
    (`shore_mask_digits/3` is binary-only for now), which could be a source
    of visually-wrong edges near river mouths specifically.

## Update 2026-09-22: root cause found, with data

Kevin sent a real classic-MoM screenshot (a smooth, flowing coastline — no
jaggedness at all). Confirmed: this is a real bug, not art style.

Ruled out the rotation-fallback theory: instrumented `fallbackStep` across a
full real-map render (see script approach below) — **0%** of tiles use a
rotated canonical match. That's not the cause.

The actual cause: **incomplete exact-mask coverage**, measured directly:
- Shore: 890 shore tiles rendered, only 558 (63%) hit an *exact* mask match.
  The other 332 (37%) fall back to `nearest_cost` — a Hamming-distance
  substitute mask, sometimes off by 2 bits (visibly wrong land/water in that
  direction).
- Hill/mountain/tundra/desert: 21–55% of tiles (varies by kind) fall back to
  the flat `00000000` "no edge" image when they actually border something
  different, because no matching edge-blend variant was found.
- Forest/grass/swamp: 100% `no_smooth`, by design — these tile types
  genuinely only ever use one image in the real game. Not a bug.

**Why exact matches are missing**: Mirror's canonicalization only tries the
4 rotations of a raw mask. The real game does something different and much
more precise — a **declarative reduction rule table**
(`SmoothingSystemEx`/`smoothingReduction`, see PR #3's notes) that collapses
any raw mask down to one that has art, via specific rules like "if two
adjacent cardinal edges are land, the corner between them must also be
land." Mirror never had this table.

**Found it.** `Server/src/external/resources/momime.server.database/Original
Master of Magic 1.31 rules.momime.xml` (277K lines, in the momime git repo —
not something we need Kevin's Drive uploads for) contains the actual
production ruleset for tileSet `TS01` ("Overland map"):
- `SS161EX` — shore's smoothing system (`TT08` = Shore, secondary type
  `TT11` = "Shore (Oceanside River Mouth)", tertiary `TT09` = Ocean). **42
  real reduction rules**, human-readable descriptions included, e.g. "If two
  adjacent edges are land, the corner between them must also be land."
- `SS161` — the land-type edge-to-grass smoothing used by hills/mountains/
  tundra/desert. **4 rules.**

Extracted and saved to
[../reference/momime-source/overland-smoothing-systems.xml](../reference/momime-source/overland-smoothing-systems.xml).

## Next step

Port `SmoothingSystemEx`'s rule-application algorithm (already documented in
PR #3's reference copy of that file) plus these 46 real rules into Mirror —
replacing the ad-hoc rotation/cost-search fallback with the exact real
reduction table. Bounded scope: 46 rules, one interpreter function, on both
the Elixir side (`shore_mask.ex`, for tests/metrics) and the JS side
(`map_hooks.js`, for actual rendering). Should drop the shore fallback rate
from 37% toward ~0%, same as the missing-tile fix did for exact masks.
