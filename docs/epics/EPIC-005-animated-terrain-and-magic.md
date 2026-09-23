# EPIC-005: Animated terrain and magic effects

**Status:** scoped, not started
**Owner:** [Kevin](https://github.com/KevinAsbury)
**Requested:** 2026-09-22, right after STORY-005 (map renders from `TERRAIN.LBX`)

## Goal

The overland map should move the way the real game's does:

- **Ocean twinkle**: water tiles cycle through their animation frames.
- **Node auras**: magic sparkle hanging in the air over the tiles around
  each node, coloured by realm:
  - **Chaos**: volcano, red/orange
  - **Nature**: bright green forest
  - **Sorcery**: intense blue lake

## What we already know

- `TERRAIN.LBX` marks 79 of its 1524 tile pointers as animated (4 frames).
  STORY-005 already puts every frame in the client atlas. The live view
  just never advances the frame. See [../reference/classic-terrain-format.md](../reference/classic-terrain-format.md).
- Nodes are their own save block (`0x006058`, 30 × 48 bytes). The aura
  tiles are almost certainly listed per node there, not derived from
  terrain. The record layout still needs verifying. See [../reference/overland-sprites-and-save-blocks.md](../reference/overland-sprites-and-save-blocks.md).
- `MAPBACK.LBX` has `MAGIC` blue/green/purple/red/white/yellow entries,
  which are the prime candidates for the sparkle art. Unconfirmed.

## Stories

- [STORY-006](../stories/STORY-006-sprite-groundwork.md): sprite groundwork (full GOG install, named-sprite catalog). Shared with EPIC-004
- [STORY-007](../stories/STORY-007-live-terrain-animation.md): live terrain animation (ocean twinkle)
- [STORY-008](../stories/STORY-008-node-auras.md): node auras (Chaos / Nature / Sorcery sparkle)
