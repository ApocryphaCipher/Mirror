# STORY-009: Overlay layers with on/off toggles

**Parent:** [EPIC-004](../epics/EPIC-004-overland-map-features.md)
**Status:** open, ready to start (can land before any overlay has data)
**Size:** small–medium

## What to do

Kevin wants to see everything at once, and to switch each kind of thing on
and off. `map_live.ex` / `map_hooks.js` already have a layer stack with
per-layer visibility + opacity (`layer_terrain[visible]`, etc.). Extend
it with **overlay layers**, drawn above terrain in this order:

1. Roads / minerals / corruption (STORY-013)
2. Node auras (STORY-008)
3. Sites: towers, fortresses, lairs, ruins, temples… (STORY-011)
4. Cities (STORY-010)
5. Units (STORY-012)

Each gets its own checkbox, all on by default, and is remembered per
browser (`localStorage`, wrapped in try/catch).

**Note:** the page currently has no CSS at all (Tailwind CLI crash, see
backlog). Fixing that first would make this UI usable. Worth doing as
part of this story or just before it.

## Definition of done

- Toggling any overlay layer redraws without reloading the save.
- Terrain-only view is still identical to STORY-005's output.
