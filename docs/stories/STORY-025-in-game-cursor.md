# STORY-025: Use the game's own mouse cursor over the map

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** open, nice-to-have (design polish), no dependencies
**Size:** small
**Requested by:** Kevin, 2026-09-23

## Goal

When the pointer is over the map, show Master of Magic's own cursor (the
gauntlet) instead of the browser arrow.

## Where the cursors are (found 2026-09-23)

**`FONTS.LBX`, inside the palette entries** (entry 2, and probably each of
entries 2–8, one per palette). Each entry is 5,472 bytes: the palette,
then a short table, then **17–18 cursor images, 16×16, column-major**
(same pixel layout as `TERRAIN.LBX` tiles), **index 0 = transparent**.

Rendering entry 2 from byte offset **736** in 256-byte steps gives
recognisable cursors, in order:

1. gauntlet holding a staff: the normal pointer
2. gauntlet holding a wand
3. red X: can't do that
4. arrow: ranged attack
5. crossed swords: melee attack
6. hourglass: wait
7. boot: move
8. a **5-frame animated** gauntlet with a sparkling wand: casting

**To confirm first:** the exact start offset (736 still shows a one-column
sliver on some images, so the true start is within a few bytes), the image
count, and whether entries 3–8 hold the same cursors or recoloured
variants. Treat the list above as a first read.

Unrelated but found in the same survey: `MAIN.LBX` entries 24–32 are named
**"unit backgrnd 1–9"** (22×28), which are candidate unit plaques for
STORY-012 (noted in `docs/reference/overland-sprites-and-save-blocks.md`).

## Approach

- Decode the cursor images once (server side next to `Mirror.TerrainLbx`,
  or client side from the `FONTS.LBX` bytes we already ship for the
  palette), render each to a small canvas, and turn it into a data-URL PNG.
- Apply it with CSS on the map viewport only:
  `cursor: url(<png>) <hotX> <hotY>, auto;`. Scale ×2 (32×32) so it stays
  readable on HiDPI, and keep it under the browsers' 128px cursor limit.
- **Hotspot:** pick by eye to match the game (probably the staff tip,
  near the top-left). Record it next to each cursor.
- **Mode-aware cursors** would feel native:
  - view: gauntlet
  - edit, painting: wand gauntlet
  - edit, space or middle-drag panning: boot
  - hovering off-map or invalid: red X
  - saving or loading: hourglass
  - The casting animation could be used for a busy state (swap frames on
    a timer; CSS can't animate cursors).
- Fall back to the normal cursor if the art isn't loaded.

## Definition of done

- Over the map, the pointer is the game's gauntlet, crisp at 1× and 2×
  pixel ratios, with the click point where the game's is.
- In edit mode the cursor changes with the tool, as listed above.
- Outside the map, the normal browser cursor is unchanged.
