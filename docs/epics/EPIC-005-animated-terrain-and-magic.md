# EPIC-005: Animated terrain and magic effects

**Status:** scoped, not started
**Owner:** [Kevin](https://github.com/KevinAsbury)
**Requested:** 2026-09-22, right after STORY-005 (map renders from `TERRAIN.LBX`)

## Goal

The overland map should move the way the real game's does:

- **Ocean twinkle**: water tiles cycle through their animation frames.
- **Node auras**: magic sparkle hanging in the air over the aura tiles around
  each melded node, coloured in the **owner's banner colour** (checked in
  live RAM; nodes belong to realms—Chaos volcano, Nature forest, Sorcery lake—but
  sparkles take the melder's colour).

## What we already know

- `TERRAIN.LBX` marks 79 of its 1524 tile pointers as animated (4 frames).
  STORY-005 already puts every frame in the client atlas. The live view
  just never advances the frame. See [../reference/classic-terrain-format.md](../reference/classic-terrain-format.md).
- Nodes are their own save block (`0x006058`, 30 × 48 bytes). The aura
  tiles are almost certainly listed per node there, not derived from
  terrain. The record layout still needs verifying. See [../reference/overland-sprites-and-save-blocks.md](../reference/overland-sprites-and-save-blocks.md).
- `MAPBACK.LBX` has `MAGIC` blue/green/purple/red/white/yellow entries,
  which are the prime candidates for the sparkle art. **Confirmed 2026-10-07:** they are `#63–#67`, one per owner colour (STORY-008).

## Stories

- [STORY-006](../stories/STORY-006-sprite-groundwork.md): sprite groundwork (full GOG install, named-sprite catalog). Shared with EPIC-004
- [STORY-007](../stories/STORY-007-live-terrain-animation.md): live terrain animation (ocean twinkle) **Implemented**, pace to tune by eye
- [STORY-008](../stories/STORY-008-node-auras.md): node auras (Chaos / Nature / Sorcery sparkle) **Done**
- [STORY-045](../stories/STORY-045-enchanted-road-shimmer.md): enchanted roads shimmer on the same clock **Done**
