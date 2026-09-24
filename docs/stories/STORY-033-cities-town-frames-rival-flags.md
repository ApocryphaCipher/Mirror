# STORY-033: Cities: Town+ frames, rival flag colours, `CITYNOWA`

**Parent:** [EPIC-004](../epics/EPIC-004-overland-map-features.md)
**Status:** open, follow-up to STORY-032
**Size:** small (mostly playing the game and taking screenshots)

## What's left

STORY-032 checked cities against the real game, but these weren't in any
screenshot:

1. **Frames 2–4.** A Town, City and Capital (size bytes 3+) on the
   overland map: is the frame still size − 1? Grow a city in the god-mode
   save (`~/DOS/MAGIC/SAVE3.GAM`), or find a rival's big city.
2. **Rival flag colours.** Get red, purple, green and blue cities on
   screen on the overland map, not only in a city screen's mini-map.
   Mirror assumes the yellow rule (ramp start + 1..3, e.g. red 200–202).
   Read the flag pixels back as palette indices; DOSBox screenshots keep
   exact colours.
3. **`MAPBACK #21` (`CITYNOWA`).** Its frames are `#20`'s without the
   stone ring. When does the game draw it? One *guess* is a city whose
   walls were destroyed; this needs a save that shows it.

## Definition of done

The three answers are in the sprite catalog, and Mirror's drawing (frame,
flag remap in `assets/js/map_overlays.js`) matches, or the catalog says
what's still unseen.
