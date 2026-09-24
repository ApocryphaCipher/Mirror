# STORY-008: Node auras (Chaos / Nature / Sorcery sparkle)

**Parent:** [EPIC-005](../epics/EPIC-005-animated-terrain-and-magic.md)
**Status:** open, ready. The sparkle art is catalogued (STORY-006). The node
record layout is in [kazzmir-save-layouts.md](../reference/kazzmir-save-layouts.md):
x/y/plane, owner, and power are checked against SAVE1, as are the aura
tile lists and type (0 Sorcery, 1 Nature, 2 Chaos). kazzmir draws sparkles
only on melded nodes, in the melder's colour; check that in the game.
**Live RAM (2026-09-24):** owner, power and aura lists checked by a real meld, and sparkles are in the **owner's** colour; see [the evaluation](../notes/2026-09-24-live-ram-evaluation.md).
**Size:** medium

## What to do

1. **Decode the node block**: `0x006058`, 30 records × 48 bytes. Find
   x/y/plane, realm (Chaos/Nature/Sorcery), owner, and the aura-tile list.
   Verify against `SAVE1.GAM`: node positions must land on the node tiles
   already visible in the `TERRAIN.LBX` render (volcano / bright forest /
   blue lake). Record the layout in [../reference/overland-sprites-and-save-blocks.md](../reference/overland-sprites-and-save-blocks.md).
2. **Identify the sparkle art**: most likely the `MAPBACK.LBX` `MAGIC`
   colour entries (STORY-006 catalog). Confirm frame count and which colour
   maps to which realm (or whether it's by *owner* banner colour instead).
3. **Draw auras** as a separate overlay layer over each aura tile, animated
   on STORY-007's clock, and toggleable (STORY-009).

## Definition of done

- Every node on both planes shows its sparkle field in the right realm
  colour, over the right tiles, matching a reference screenshot from the
  real game.
