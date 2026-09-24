# STORY-013: Specials and bonuses (ores, gems, nightshade, wild game…), roads and corruption

**Parent:** [EPIC-004](../epics/EPIC-004-overland-map-features.md)
**Status:** open, ready. Minerals values, terrain-flag bits (road
`0x08`, enchanted road `0x10`, corruption `0x20`) and road-piece
selection are in [kazzmir-save-layouts.md](../reference/kazzmir-save-layouts.md); the roads are checked
against a DOSBox shot. **Don't lose the specials:** [Kevin](https://github.com/KevinAsbury)
(2026-09-23) flagged the bonus tiles as easy to forget next to lairs and
towers. They get their own map layer and toggle (STORY-009), their own
editing tool later (STORY-018/028), and a place in the edit checker
(STORY-029).
**Live RAM (2026-09-24):** minerals 4, 5, 7, 64, 128 checked on screen via Surveyor. See [the evaluation](../notes/2026-09-24-live-ram-evaluation.md).
**Size:** medium

## The specials / bonuses (map resources)

The classic game's terrain specials, drawn from the `MAPBACK.LBX` `SITES`
icons (see the sprite reference):

- **Ores and metals:** iron, coal, silver, gold, mithril, adamantium
- **Crystals and gems:** gems, quork crystals, crysx crystals (the
  "power" specials)
- **Food and herbs:** wild game, nightshade
- **Worked-site overlays:** mine, lumber camp, hunter's lodge (verify
  whether these are specials or city-worked markers)

Source data is most likely the **minerals map** (`0x013554`, 1 byte per
tile). Decode which value means which special, and check it against a
known save, the same way the terrain offsets were verified.

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
