# STORY-009: Overlay layers with on/off toggles

**Parent:** [EPIC-004](../epics/EPIC-004-overland-map-features.md)
**Status:** done 2026-09-23 (the layers are empty until their stories land)
**Size:** small–medium

## What to do

[Kevin](https://github.com/KevinAsbury) wants to see everything at once, and to switch each kind of thing on
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

(The missing-CSS problem noted here earlier is fixed by #10; see backlog.)

## Definition of done

- Toggling any overlay layer redraws without reloading the save.
- Terrain-only view is still identical to STORY-005's output.

## Outcome (2026-09-23)

- Overlays draw on their own transparent canvas (`#map-overlays`, hook
  `MapOverlays` in `assets/js/map_overlays.js`), stacked over the terrain
  canvas inside a `[data-map-stage]` wrapper that `MapViewport` now
  pans/zooms. Sprites can overhang their tile without the terrain's
  per-tile redraws clipping them, and toggling a layer never touches the
  terrain canvas.
- A **Layers** panel (bottom right, collapsible) lists Units, Cities,
  Sites, Node auras, Roads & specials, top layer first, all on by default,
  remembered per browser in `localStorage` (`mirror.overlayLayers.v1`,
  guarded with try/catch). Clicks in the panel don't pan the map.
- The layer list lives in one place: `@overlay_layers` in `map_live.ex`.
- **How a story fills its layer:** add a draw function to `DRAWERS` in
  `map_overlays.js` (`(ctx, items, {tileSize})`, device pixels; terrain
  tiles are drawn `tileSize` square) and send the items with
  `push_event(socket, "overlay_data", %{layer: "cities", items: [...]})`.
  Remember `push_event` returns the socket.
- Verified in the browser: terrain canvas pixels hash-identical to `main`
  for SAVE1 Arcanus (`043978cb…`); the overlay canvas has the same box as
  the terrain at every zoom; toggles persist across reloads; hover still
  picks the right tile. Not yet exercised: an actual draw, since no layer
  has data (STORY-010 will be the first).

