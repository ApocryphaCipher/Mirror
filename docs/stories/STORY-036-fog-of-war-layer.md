# STORY-036: Fog-of-war layer, off by default

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** open, nice-to-have
**Size:** small (extra credit: small to medium)
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

Mirror doesn't have to copy the game's fog drawing (Kevin, 2026-09-24).

1. **Black fog:** paint every tile with value 0 solid black, and leave
   1–15 clear. This is the story.
2. **Extra credit, partly explored tiles (1–14):** Mirror's own look,
   not the game's. Soften the edge with transparency and a dither, so
   the fog fades into the explored area instead of ending in a hard
   grid line. For example:
   - The four bits are the tile's four quarters or sides (*guess*, see
     the reference doc). Fade or dither the unexplored parts, and set
     their strength from how many bits are missing.
   - A plain fallback: a partial tile gets a translucent black, stronger
     when fewer bits are set.

   How the game itself draws these tiles is a very-low-priority backlog
   item; nothing here waits on it.

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
- Extra credit: partly explored tiles fade into the explored area,
  with no hard grid edges.
