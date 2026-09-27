# EPIC-004: Render towns, forts, towers, tombs, and other overland features

**Status:** done. Cities are decoded and rendered with owner flags and population-driven frames (STORY-010, STORY-032, STORY-033). Sites are decoded (`Mirror.SaveFile.Sites`) and drawn (STORY-011). Roads, minerals/specials, and corruption are decoded and rendered (STORY-013). Units are decoded and rendered with banner-colour plaques (STORY-012). Rival flag colours beyond yellow and `CITYNOWA` are unresolved but moved to backlog.md as very-low-priority, not tracked as remaining epic work.
Scope widened by [Kevin](https://github.com/KevinAsbury) to include **units** (figure on a banner-colour
plaque) and **per-layer on/off toggles**. Sprite and save-block survey:
[../reference/overland-sprites-and-save-blocks.md](../reference/overland-sprites-and-save-blocks.md).
**Owner:** Kevin
**Found:** 2026-09-22, Kevin: "The towns, forts, towers, tombs, and other
overland stuff is not showing either."

## What this was (historical context from 2026-09-22)

When first investigated on 2026-09-22, Mirror had never parsed or rendered
cities, towers, lairs, ruins, or any other point-of-interest. Today,
cities are parsed (`Mirror.SaveFile.Cities`) and rendered (`map_overlays.js`),
and encounter sites, towers and nodes are parsed (`Mirror.SaveFile.Sites`).

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
  `+28` current production, `+31..+66` buildings statuses (including `+66`
  walled flag), `+67..+92` enchantment presence flags.

"Fortresses," "Towers," and "Encounter zones" (which almost certainly
covers lairs, ruins, ancient/fallen temples, and Towers of Wizardry — the
"tombs" Kevin mentioned) were originally wiki-only, but the layouts have since
been decoded and verified in `Mirror.SaveFile.Sites` and live RAM notes.

## Implementation approach

1. **Parse the blocks.** Implemented: `Mirror.SaveFile.Cities` (X, Y, plane,
   name, owner, size, pop, buildings, enchantments) and `Mirror.SaveFile.Sites`
   (nodes, towers, encounter zones).
2. **Get the icon art.** Classic LBX art from `MAPBACK.LBX` is used
   (the MOMIME PNG fallback and indexing scripts discussed during early scoping
   were superseded and deleted).
3. **Render overlay markers.** Draw functions in `assets/js/map_overlays.js`
   render cities (`MAPBACK #20`) with owner banner colours and size-appropriate
   frames. (STORY-032 confirmed in DOSBox that walls do not alter the overland
   sprite; wall status is decoded and displayed in the hover readout rather than
   drawn on the map). Follow-ups will render sites and unit plaques.
4. **Wire into LiveView payload.** `map_live.ex` pushes parsed city and
   overlay records alongside terrain layers.

## Stories

Suggested order: STORY-006 → STORY-009 → STORY-010 → STORY-012 →
STORY-011 → STORY-013.

- [STORY-006](../stories/STORY-006-sprite-groundwork.md): sprite groundwork (full GOG install, named-sprite catalog). **Done**: catalog in [../reference/overland-sprites-and-save-blocks.md](../reference/overland-sprites-and-save-blocks.md)
- [STORY-009](../stories/STORY-009-overlay-layer-toggles.md): overlay layers with on/off toggles. **Done**
- [STORY-010](../stories/STORY-010-cities.md) (**Done**): cities
- [STORY-032](../stories/STORY-032-cities-walls-labels-verify.md) (**Done**): cities follow-up: walls, name labels, check against the real game
- [STORY-033](../stories/STORY-033-cities-town-frames-rival-flags.md) (**Done**): cities: Town+ frames, rival flag colours, `CITYNOWA` (frame question resolved; flags/CITYNOWA moved to backlog.md)
- [STORY-011](../stories/STORY-011-sites-towers-lairs.md) (**Done**): towers, fortresses, lairs, ruins and other sites
- [STORY-012](../stories/STORY-012-units-with-banner-plaques.md) (**Done**): units with banner-colour plaques
- [STORY-013](../stories/STORY-013-roads-minerals-corruption.md) (**Done**): specials and bonuses (ores, gems, nightshade, wild game…), roads, corruption

Superseded from the original scoping above: the plan to use MOMIME
`overland/cities` / `overland/mapFeatures` PNGs. Classic LBX art is the
path now.

## Open question

Kevin's original message ordered these as "towns, forts, towers, tombs" —
worth clarifying whether "forts" means the wiki's "Fortresses data" block
specifically (which might be wizard-summoning-related, not a generic
building type — needs checking what that block actually represents) or is
just informal phrasing for fortified cities/towers generally.
