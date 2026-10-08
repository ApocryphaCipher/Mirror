# STORY-008: Node auras (Chaos / Nature / Sorcery sparkle)

**Parent:** [EPIC-005](../epics/EPIC-005-animated-terrain-and-magic.md)
**Status:** implemented and checked against the real game (2026-10-07). Nodes are
decoded (owner, power, aura tiles) and the sparkles are drawn on owned nodes only.
**Live RAM (2026-09-24):** owner, power and aura lists checked by a real meld, and sparkles are in the **owner's** colour; see [the evaluation](../notes/2026-09-24-live-ram-evaluation.md).
**Size:** medium

## What to do

1. **Decode the node block**: `0x006058`, 30 records × 48 bytes. Find
   x/y/plane, realm (Chaos/Nature/Sorcery), owner, and the aura-tile list.
   Verify against `SAVE1.GAM`: node positions must land on the node tiles
   already visible in the `TERRAIN.LBX` render (volcano / bright forest /
   blue lake). Record the layout in [../reference/overland-sprites-and-save-blocks.md](../reference/overland-sprites-and-save-blocks.md).
2. **Identify the sparkle art**: most likely the `MAPBACK.LBX` `MAGIC`
   colour entries (STORY-006 catalog). Frame count and palette mappings
   can be verified against live screenshots.
3. **Draw auras** as a separate overlay layer over each aura tile, animated
   on STORY-007's clock, and toggleable (STORY-009).

## Definition of done

- Every melded node on both planes shows its sparkle field in the owner's
  banner colour (unmelded nodes show no sparkles), over the right tiles,
  matching a reference screenshot from the real game.

## What was built

- **`Mirror.SaveFile.Sites`:** each node now carries `power` and `aura_tiles` (the
  first `power` `{x, y}` pairs from `+5` and `+25`, off-map pairs dropped, capped at
  the 20 stored).
- **`Mirror.OverlaySprites`:** `sparkles`, `MAPBACK #63–#67` keyed by banner colour
  (6 frames of 20×18); `#68` is blank and unused.
- **`MapLive`:** an `auras` overlay of every aura tile of every **owned** node on the
  viewed plane, `%{x, y, banner, i}`, with `i` the tile's place in the node's list.
  It is pushed with the other save-derived items, so it follows a save loaded in
  another tab and a discard, and it is not re-pushed on a tile edit.
- **`map_overlays.js`:** an `auras` drawer on the shared clock (600 ms,
  `phaseAt`) and the shared "Animate terrain" toggle, frame `(step + i) mod 6`,
  drawn in the sprite's own colours (`image(..., false)` skips the banner remap,
  which would turn the green sparkle brown). The layer's own toggle (Layers panel)
  still hides it.
- The overlay canvas redraws only while an aura is on screen and the tab is visible.

## Checked in the real game (2026-10-07)

SAVE4 (SAVE3 with three nodes owned by Freya, made for this) was loaded in the
DOSBox fork, and the game's sparkles compared with Mirror's art:

- **The art and the tiles:** all 128 screenshot crops of a Chaos node's eight aura
  tiles matched a `#67` frame on every opaque pixel.
- **The order and the pace:** frames advance 0, 1, 2, … 5 in order, one per step,
  mean 0.578 s; and tile *i* shows frame `(step + i) mod 6` (the eight tiles showed
  4, 5, 0, 1, 2, 3, 4, 5 at one moment).
- **Mirror's canvas** (the Docker image, SAVE4 loaded, the auras layer alone): over
  all 6 phases, the 23 aura tiles of the three nodes, 565,248 device pixels, drawn
  exactly the sprite frame `(phase + i) mod 6` with 0 wrong pixels and 0 wrong colours.
  The green entry drawn as the drawer does stays green (51 of 63 pixels); remapped as
  a banner it would be brown.
- **Unowned nodes** show nothing, and only the viewed plane's nodes are pushed.

## Not yet seen

Nobody has watched Mirror's sparkles animate on screen: the browser pane was hidden,
so the clock was stepped by hand. The Chaos and Nature nodes' sparkles (and the green,
blue, red and purple art) were checked by pixels or by the sprite dump, not against a
real-game screenshot of an owner of that colour. Other realms' sparkle in the owner's
colour is from the docs and the Sorcery node's earlier meld.
