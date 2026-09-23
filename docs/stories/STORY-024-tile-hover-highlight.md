# STORY-024: Highlight the tile under the cursor

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** open, nice-to-have (design polish), no dependencies
**Size:** small
**Requested by:** Kevin, 2026-09-23

## Goal

When the mouse is over the map, make the tile under it obvious. Today the
only cue is the text readout in the corner.

Kevin's ideas, either or both:

- **Glow:** a soft green border / outer glow around the tile.
- **Lift:** the tile "elevates", scaling up slightly (e.g. 1.1×) with a
  drop shadow, as if picked up.

## Approach

- **Don't redraw the map canvas for this.** Use one absolutely positioned
  overlay `<div>` inside `#map-viewport`, sized to one tile and moved with
  a CSS transform. It rides the same pan/zoom transform maths as the canvas
  (`MapViewport` already knows `tx`, `ty`, `scale`).
- **Compute the tile client-side** from the pointer (like `tileFromEvent`),
  not from the server's hover round-trip, so the highlight tracks the mouse
  with no latency. The server readout can keep its own pace.
- **Glow:** `box-shadow` / `outline` in the accent green, with a short
  fade/pulse (`@keyframes`, respecting `prefers-reduced-motion`).
- **Lift:** copy the tile's pixels from the canvas into the overlay (a
  small canvas, or `background` from the atlas), then
  `transform: scale(1.1)` + shadow, `image-rendering: pixelated`.
- **Mode-aware:**
  - **View:** subtle glow.
  - **Edit:** stronger, and can double as a **brush preview**, showing the
    brush tile ghosted over the target before you click. That also
    softens STORY-023's "did my click do anything?" problem.
  - Hide it while panning and when the pointer leaves the map.

## Definition of done

- The hovered tile is clearly marked at every zoom level (25–400%) and
  follows the cursor without lag.
- No full-canvas redraws on hover (check with the Performance panel).
- Reduced-motion users get a static highlight.
