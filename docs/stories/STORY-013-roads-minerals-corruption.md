# STORY-013: Roads, minerals and corruption

**Parent:** [EPIC-004](../epics/EPIC-004-overland-map-features.md)
**Status:** open, blocked on STORY-006. Lower priority.
**Size:** medium

## What to do

- **Roads / enchanted roads**: probably bits in the terrain-flags map
  (`0x01cbb8`). Draw `MAPBACK.LBX` `ROADS` / `E_ROADS`, choosing the
  direction piece from neighbouring road tiles (as the game does).
- **Minerals / specials**: minerals map (`0x013554`). Draw the `SITES`
  coal/iron/silver/gold/gems/mithril/adamantium/quork/crysx/nightshade/
  wild game icons.
- **Corruption**: `CORRUPT`, probably another terrain-flags bit.

The old `drawFlagOverlays` / `drawMineralOverlay` code guessed at these
bits; the 2026-09-22 recon found the flags histogram suspicious (19% of
tiles = `0xFF`). Re-derive the bit meanings rather than reusing those
guesses.

## Definition of done

- Roads, minerals and corruption in `SAVE1.GAM` match the real game's
  overland view.
