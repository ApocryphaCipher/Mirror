# STORY-032: Cities: walls, name labels, and a check against the real game

**Parent:** [EPIC-004](../epics/EPIC-004-overland-map-features.md)
**Status:** open, follow-up to STORY-010
**Size:** small–medium

## What to do

1. **Walls.** Draw `MAPBACK.LBX #20` (walled) instead of #21 for cities
   with City Walls. The buildings are the 1/0xFF/0 flags from record
   `+34` (momedit reads them as a list; its building enum isn't in our
   copy of the source). Find which flag is City Walls, grounded in a save
   where a city is known to have walls (build them in-game, or edit a
   copy of a save and check the game shows them).
2. **Name labels.** Show the city name: in the hover readout at least,
   optionally as a label under the sprite (a separate "City names" toggle
   in the Layers panel?).
3. **Check against the game.** Compare SAVE1 in the real game (DOSBox)
   with Mirror: is the `+19` byte the size class that picks the frame, and
   does the game recolour the flag the way Mirror does (216–218 shifted
   into the owner's banner ramp; browns for neutral)? Is the sprite placed
   where the game puts it (Mirror centres it on the tile)? Record the
   answer in the sprite catalog and drop the *guess* marks.

## Definition of done

- Walled cities show walls; names are visible; the three guesses above are
  confirmed or corrected in the catalog.
