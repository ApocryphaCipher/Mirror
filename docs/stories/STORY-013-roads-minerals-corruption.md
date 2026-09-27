# STORY-013: Specials and bonuses (ores, gems, nightshade, wild game…), roads and corruption

**Parent:** [EPIC-004](../epics/EPIC-004-overland-map-features.md)
**Status:** **Done** (2026-09-26). Roads, minerals/specials, and corruption decoded and rendered.
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

## Outcome

- Pure module `Mirror.SaveFile.Roads` decodes roads, specials, and corruption from the `:terrain_flags` and `:minerals` save blocks (`0x01cbb8` and `0x013554`).
- Road piece selection reuses `Mirror.Engine.Topology` (60×40, `wrap_x: true`, `wrap_y: false`) to connect to road neighbours in N, NE, E, SE, S, SW, W, NW order starting from the centre piece (`:c`).
- Normal roads (bit `0x08`, `MAPBACK #45..#53`, 1 frame) and enchanted roads (bit `0x10`, `MAPBACK #54..#62`, frame 0) are selected based on the tile flag; connected neighbours with either road bit connect.
- Minerals map values 1–9, 64, 128 decode to iron, coal, silver, gold, gems, mithril, adamantium, quork crystals, crysx crystals, wild game, and nightshade (`MAPBACK #78..#86`, `#92`, `#91`).
- Corruption bit `0x20` decodes to a corruption item (`MAPBACK #77`, 22×18).
- `Mirror.OverlaySprites` loads the road, enchanted road, special, and corruption sprite entries from `MAPBACK.LBX`.
- `MapLive` pushes the combined `"roads"` layer items via `push_map_layers/1`.
- `assets/js/map_overlays.js` implements `DRAWERS.roads`, drawing road pieces, special icons, and corruption centered on the tile and scaled by `tileSize / TILE_ART_W`.
- Unit tests in `test/mirror/save_file/roads_test.exs` test piece selection (0, 1, multiple neighbours, x-wrap at 0/59, y-clamp at 0/39), enchanted vs. normal road choice, all 11 minerals values, and corruption bit handling using synthetic binary fixtures.
- Real-file and LiveView tests in `test/mirror_web/live/map_live_edit_test.exs` and `test/mirror/overlay_sprites_test.exs` verify `SAVE1.GAM` and `MAPBACK.LBX` integration.
- *Unverified*: in-game appearance of corruption tiles (no corruption tiles in `SAVE1`–`SAVE9`).
