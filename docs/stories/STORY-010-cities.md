# STORY-010: Cities on the map

**Parent:** [EPIC-004](../epics/EPIC-004-overland-map-features.md)
**Status:** done 2026-09-23 (walls, labels and a check against the real game → STORY-032)
**Size:** medium

## What to do

1. **Parse** the cities block: `0x008aac`, 100 × 114 bytes, live count at
   `0x0009e0`. Fields cross-validated by momedit: `+15` x, `+16` y,
   `+17` plane, `+18` owner, `+20` population. Name is at the start of
   the record (verify).
2. **Owner colour**: owner → wizard record (`0x0009e8 + n × 0x4c8`) →
   banner colour at `+0x16`.
3. **Draw** `MAPBACK.LBX` `MAPCITY` (frame by city size, colour by owner;
   check how the real game tints it) on the city's tile, with the name
   label optional.
4. Walled / enchanted variants are a follow-up.

## Definition of done

- All cities in `SAVE1.GAM` appear on the right tiles and planes, in their
  owner's colour, matching the real game's overland view.

## Outcome (2026-09-23)

- `Mirror.SaveFile.Cities.parse/1` reads the live records (count at
  `0x9e0`); `Mirror.SaveFile.Wizards.banners/1` maps owner → banner from
  the wizard records (`+0x16`; owner 5 is neutral). SAVE1: 27 cities, 16 on
  Arcanus and 11 on Myrror; owners 0–4 are Freya (yellow), Sharee (red),
  Tlaloc (purple), Jafar (blue), #4 (green); 22 cities are neutral.
- `Mirror.OverlaySprites` sends MAPBACK #20/#21 as palette indices plus the
  game palette; the `cities` drawer in `map_overlays.js` draws the frame
  for the `+19` size class, centred on the tile, flag recoloured to the
  owner's banner ramp (see the catalog). MapLive pushes the plane's cities
  whenever it pushes the tile assets (mount, load, plane switch).
- Checked in the browser on SAVE1: Deventor (38, 21) yellow, Sidon
  (55, 29) blue, Bloodrock on Myrror (54, 23) purple, neutral Steyr
  (47, 16) at the size-2 frame; Myrror shows only Myrror's cities; the
  Cities toggle clears and restores the layer exactly.
- Not done (STORY-032): walled cities (every city uses the unwalled
  sprite), name labels, and confirming the size-class frame and the flag
  recolour against the real game.

