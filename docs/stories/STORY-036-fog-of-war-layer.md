# STORY-036: Fog-of-war layer, off by default

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** open, nice-to-have
**Size:** small (flat black), medium (the game's soft edges)
**Requested by:** [Kevin](https://github.com/KevinAsbury), 2026-09-24

## Goal

A **Fog of war** checkbox in the Layers panel, **off by default**. When
it's on, black fog is painted over the tiles the player hasn't explored,
so you see the map as the player does. When it's off, Mirror shows the
whole map, as it does today. Other layers (cities, the Surveyor,
[STORY-035](STORY-035-settleable-tiles-overlay.md)'s settleable tiles)
keep showing everything either way.

## What's known

The save's explored map
([wizard-record-and-exploration.md](../reference/wizard-record-and-exploration.md#explored-map-fog-of-war)):

- one byte per tile at `0x014814`, Arcanus then Myrror;
- 0 = unexplored, 15 = fully explored;
- 1–14 = partly explored, along the edge of the explored area (SAVE9:
  195 tiles at 15, 84 at 1–14).

Mirror already decodes it as the `exploration` layer.

## Steps

1. **Flat fog:** paint every tile with value 0 solid black, and leave
   1–15 clear. This is enough to be useful.
2. **Soft edges, like the game:** *guess:* each of the four bits is one
   side or quarter of the tile, and the game draws partly explored tiles
   with the `MAPBACK` edge masks (`#0–#13`). Confirm first:
   - set one tile to 1, 2, 4 and 8 in turn with the DOSBox fork;
   - screenshot each (the fork's screenshot endpoint);
   - then draw the matching mask over those tiles.
   - Write the result into the reference doc.

## Notes

- Draw it as a client-side overlay like the other layers, from the
  `exploration` layer pushed with `overlay_data`.
- It must follow edits: STORY-029's "show everything" talk is about
  editing past the fog, and this layer shows where that fog is.
- The explored map is the human player's only (kazzmir; the AI wizards'
  exploration isn't in this block).

## Done when

- The Layers panel has a Fog of war checkbox, unchecked on load.
- Checked, the unexplored tiles on the current plane are black, matching
  the game on a real save; switching planes switches the fog.
- If step 2 is done, the edge tiles match a game screenshot.
