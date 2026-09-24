# EPIC-004: Render towns, forts, towers, tombs, and other overland features

**Status:** scoped into stories 2026-09-22 (STORY-006, STORY-009–013).
Scope widened by [Kevin](https://github.com/KevinAsbury) to include **units** (figure on a banner-colour
plaque) and **per-layer on/off toggles**. Sprite and save-block survey:
[../reference/overland-sprites-and-save-blocks.md](../reference/overland-sprites-and-save-blocks.md).
**Owner:** Kevin
**Found:** 2026-09-22, Kevin: "The towns, forts, towers, tombs, and other
overland stuff is not showing either."

## What this actually is

Not a bug — confirmed via `grep -rin "cit\(y\|ies\)\|fortress\|tower" lib/
lib_web/` returning **zero results**. Mirror has never parsed or rendered
cities, towers, lairs, ruins, or any other point-of-interest on the
overland map. This is new scope, not a regression.

## What we know about where this data lives

The save file has (at least) two relevant blocks, per the
[Save Game Format wiki](https://masterofmagic.fandom.com/wiki/Save_Game_Format)
(already used successfully for the terrain offsets) — **and independently
cross-validated** against a second source, the real `momedit` save editor
(see [../reference/momedit-source/](../reference/momedit-source/)):

| Block | Offset | Length | Qty | Cross-validated? |
| --- | --- | --- | --- | --- |
| Cities | `0x008aac` | `0x0072` (114 bytes) | 100 | Yes — `momedit`'s `City.CITY_OFFSET = 0x8aac`, `CITY_OBJ_LEN = 114`, exact match |
| Fortresses data | `0x0065f8` | `0x0004` | 6 | Wiki only |
| Towers data | `0x006610` | `0x0004` | 6 | Wiki only |
| Encounter zones data | `0x006628` | `0x0018` | 99 + 3 | Wiki only |

The Cities block is the well-grounded one — `momedit` gives real per-field
byte offsets within each 114-byte record (from its `Load`/`Save` methods):

- `+14` race, `+15` X, `+16` Y, `+17` plane (world), `+18` owner,
  `+20` population, `+21` worker/farmer ratio, `+24` growth rate (int16),
  `+28` current production, `+34` active spells bitmask, `+67` enchantment
  presence flags.

"Fortresses," "Towers," and "Encounter zones" (which almost certainly
covers lairs, ruins, ancient/fallen temples, and Towers of Wizardry — the
"tombs" Kevin mentioned) are **wiki-only so far** — `momedit` doesn't
implement these at all (checked; no matching class exists in its source).
These need their own verification before trusting the byte layout.

## What's needed to actually render this

1. **Parse the blocks.** New `Mirror.SaveFile` extraction for cities (X/Y/
   plane/name/owner at minimum to start) and encounter zones/towers
   (X/Y/plane/type at minimum). Cities is the safer starting point — two
   sources agree on its layout; encounter zones only has one.
2. **Get the icon art.** *Update 2026-09-22:* prefer classic art now that
   the full GOG install is available (see EPIC-002). City/tower/lair
   sprites are most likely in `MAPBACK.LBX` (unverified, from memory; check
   with `/tile-probe` and the `FONTS.LBX` palette). The MOMIME fallback
   below still works. The MOMIME resource pack (same source as PR #4's
   terrain art) has `overland/cities` and `overland/mapFeatures` folders —
   **not yet copied** into `resources/` (PR #4 only pulled
   `overland/terrain`). Need to pull those in and extend
   `scripts/build_momime_resources_index.sh` accordingly, or fold them into
   one script.
3. **Render overlay markers.** New draw functions in `map_hooks.js`
   (there's precedent — `drawFeatureOverlays`/`drawEmbeddedSpecialOverlay`
   already exist for a different purpose and show the pattern: pick an
   entry from a resource group, draw on top of the base tile). Cities
   likely need something fancier eventually (different art per race/size
   per the wiki's own city-view assets), but a single marker per city is a
   reasonable first cut.
4. **Wire it into the LiveView payload.** `push_tile_assets`/`map_live.ex`
   would need to include parsed city/feature records alongside the terrain
   layers it already pushes.

## Stories

Suggested order: STORY-006 → STORY-009 → STORY-010 → STORY-012 →
STORY-011 → STORY-013.

- [STORY-006](../stories/STORY-006-sprite-groundwork.md): sprite groundwork (full GOG install, named-sprite catalog). **Done**: catalog in [../reference/overland-sprites-and-save-blocks.md](../reference/overland-sprites-and-save-blocks.md)
- [STORY-009](../stories/STORY-009-overlay-layer-toggles.md): overlay layers with on/off toggles. **Done**
- [STORY-010](../stories/STORY-010-cities.md) (**Done**): cities
- [STORY-032](../stories/STORY-032-cities-walls-labels-verify.md) (**Done**): cities follow-up: walls, name labels, check against the real game
- [STORY-033](../stories/STORY-033-cities-town-frames-rival-flags.md): cities: Town+ frames, rival flag colours, `CITYNOWA`
- [STORY-011](../stories/STORY-011-sites-towers-lairs.md): towers, fortresses, lairs, ruins and other sites
- [STORY-012](../stories/STORY-012-units-with-banner-plaques.md): units with banner-colour plaques
- [STORY-013](../stories/STORY-013-roads-minerals-corruption.md): specials and bonuses (ores, gems, nightshade, wild game…), roads, corruption

Superseded from the original scoping above: the plan to use MOMIME
`overland/cities` / `overland/mapFeatures` PNGs. Classic LBX art is the
path now.

## Open question

Kevin's original message ordered these as "towns, forts, towers, tombs" —
worth clarifying whether "forts" means the wiki's "Fortresses data" block
specifically (which might be wizard-summoning-related, not a generic
building type — needs checking what that block actually represents) or is
just informal phrasing for fortified cities/towers generally.
