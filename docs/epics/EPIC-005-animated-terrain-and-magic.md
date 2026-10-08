# EPIC-005: Animated terrain and magic effects

**Status:** done (2026-10-07). Kevin watched the terrain, the node sparkles and the enchanted roads animate in his browser.
**Owner:** [Kevin](https://github.com/KevinAsbury)
**Requested:** 2026-09-22, right after STORY-005 (map renders from `TERRAIN.LBX`)

## Goal

The overland map should move the way the real game's does:

- **Ocean twinkle**: water tiles cycle through their animation frames.
- **Node auras**: magic sparkle hanging in the air over the aura tiles around
  each melded node, coloured in the **owner's banner colour** (checked in
  live RAM; nodes belong to realms—Chaos volcano, Nature forest, Sorcery lake—but
  sparkles take the melder's colour).
- **Enchanted roads**: the road art's colour shimmer (STORY-045, added 2026-10-07).

Everything steps together on the game's own pace, **0.6 s a step**, measured from
DOSBox screenshots; a toggle ("Animate terrain", in the Layers panel) turns it off,
and it pauses while the tab is hidden.

## What we already know

- `TERRAIN.LBX` marks 79 of its 1524 tile pointers as animated (4 frames).
  STORY-005 already puts every frame in the client atlas. STORY-007 now advances
  them, redrawing only the animated cells (300 of them on one real Arcanus). See [../reference/classic-terrain-format.md](../reference/classic-terrain-format.md).
- Nodes are their own save block (`0x006058`, 30 × 48 bytes). The aura
  tiles are listed per node there (the first `power` pairs), and the owner byte is
  all a meld changes; checked in the game (STORY-008). See
  [../reference/kazzmir-save-layouts.md](../reference/kazzmir-save-layouts.md).
- `MAPBACK.LBX` has `MAGIC` blue/green/purple/red/white/yellow entries,
  which are the prime candidates for the sparkle art. **Confirmed 2026-10-07:** they are `#63–#67`, one per owner colour (STORY-008).

## Stories

- [STORY-006](../stories/STORY-006-sprite-groundwork.md): sprite groundwork (full GOG install, named-sprite catalog). Shared with EPIC-004
- [STORY-007](../stories/STORY-007-live-terrain-animation.md): live terrain animation (ocean twinkle) **Done**, paced at the game's 0.6 s
- [STORY-008](../stories/STORY-008-node-auras.md): node auras (Chaos / Nature / Sorcery sparkle) **Done**
- [STORY-045](../stories/STORY-045-enchanted-road-shimmer.md): enchanted roads shimmer on the same clock **Done**
