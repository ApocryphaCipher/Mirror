# STORY-004: Add river/river-mouth/volcano/node kinds to classification and rendering

**Parent:** [../epics/EPIC-003-terrain-value-classification.md](../epics/EPIC-003-terrain-value-classification.md)
**Status:** blocked on STORY-003 (need the real value table first)
**Size:** medium — mechanical once STORY-003 lands, since the smoothing
algorithm and art are already in place

## What this covers

Once STORY-003 delivers a real terrain-value table, wire it in on both
sides that currently duplicate terrain classification:

- **Elixir**: `Mirror.Map.terrain_type/1` /
  `Mirror.Quality.ShoreMask.terrain_base_kind_for_value/1` and their
  `@terrain_kind_by_base_id` table.
- **JS**: `map_hooks.js`'s `TERRAIN_KIND_BY_BASE_ID` and
  `terrainKindFromBaseId`.

Both need the full corrected table, not just "add river" — the existing
16-entry tables are wrong in more places than just the missing river/
volcano/node entries (see STORY-003 for why).

## Why this is mechanical, not another research task

The hard part — the real smoothing/rotation algorithm and the real tile
art — is **already done**:

- River uses smoothing system `SS16` per the real MOMIME production
  ruleset (`docs/reference/momime-source/overland-smoothing-systems.xml`),
  already ported in `Mirror.Quality.SmoothingRules` and wired through
  `MomimePngIndex`'s lookup-table generation (PR #4). Nothing new to build
  there — `SmoothingRules.build_lookup("SS16")` already works.
- The `overland/terrain/{plane}/river/` art (86 files) is already sitting
  in `resources/` from PR #4's terrain-folder copy — it's just currently
  unreachable because no tile ever classifies as `"river"`.
- Volcano/node types (`TT12`–`TT16`) use `SS1` (no smoothing, single
  image) per the same production ruleset — even simpler, just needs the
  classification to route there.

So this story is: fix the value→kind table, add `"river"`/`"volcano"`/
node-variant handling to the existing kind-dispatch logic
(`adjMaskForKind`, `resolveMomimePathForKind`, the `smoothing_kind_systems`
map in `MomimePngIndex`), and confirm rendering. Should not require new
algorithm work.

## Open sub-question: rivers as terrain type vs. overlay

The Fandom wiki's `Terrain` page lists River/River Mouth as terrain types
alongside Grassland/Forest/etc. — but a fragment on the `Myrror` wiki page
said "Rivers are generated more akin to map objects, rather than terrain
[type]," which could mean rivers are drawn as an overlay on top of a base
land tile rather than being their own base terrain byte value. Worth
resolving early in this story (probably resolves itself once STORY-003's
table is in hand — if raw values map cleanly to a River type, it's a base
type; if not, it's likely encoded via `terrain_flags` instead, which
would change where this story's classification logic lives).

## Definition of done

- Real save (`SAVE1.GAM`) renders visible rivers matching their real
  in-game positions (needs a reference screenshot or Kevin's own
  recollection of the map to confirm placement, not just "something blue
  and squiggly appears").
- Volcano and node-variant tiles render as their own distinct art, not
  misclassified as a neighboring plain type.
- `mix test` still green; add coverage for the corrected table similar to
  the existing `ShoreMaskTest`/`SmoothingRulesTest` pattern.
