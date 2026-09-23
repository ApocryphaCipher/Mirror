# STORY-015: View mode: the map fills the window

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** open, ready to start (STORY-014 first makes this easier)
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
