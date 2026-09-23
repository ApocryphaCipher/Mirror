# STORY-015: View mode: the map fills the window

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** done 2026-09-23. The map fits the window on load. Wheel zooms
around the cursor in fixed steps (25%–400%); drag pans (clamped so the map
can't be lost); double-click or the % button re-fits; the −/%/+ control sits
bottom-right. The header has a plane switch, the save name, compact Load, and
Lab. The hover readout shows plane, (x, y), and tile number (dec + hex).
Pan/zoom is a CSS transform on the already-rendered canvas
(`assets/js/map_viewport.js`), so it never re-renders, and pixels stay crisp
via `image-rendering: pixelated`.
**Deferred:** the **Edit** button (STORY-016), overlay toggles (STORY-009),
and city/site/unit info in the readout (as EPIC-004 lands). Pinch-zoom on
touch devices isn't implemented; wheel and trackpad scroll zoom are.
**Size:** medium

## What to do

- The map canvas fills the viewport below a slim header, with **pan**
  (drag) and **zoom** (wheel / pinch, snapped to integer scales so pixels
  stay crisp).
- Slim header: plane switch (Arcanus / Myrror), **Load save** (a compact
  control, not a raw path field; keep path entry for now), overlay layer
  toggles (STORY-009), and **Edit**.
- **Hover readout**: a small tooltip or status line with x, y, plane,
  terrain, and (as EPIC-004 lands) the city / site / unit stack on that tile.
- Works at laptop widths; nothing scrolls horizontally.

## Definition of done

- Opening `/arcanus` with a save loaded shows essentially just the map.
  All other tooling is one click away (Edit) or on `/lab`.
