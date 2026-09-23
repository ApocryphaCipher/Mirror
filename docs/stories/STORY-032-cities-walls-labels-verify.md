# STORY-032: Cities: walls, name labels, and a check against the real game

**Parent:** [EPIC-004](../epics/EPIC-004-overland-map-features.md)
**Status:** open, follow-up to STORY-010
**Size:** small–medium

## What to do

1. **Walls.** Find how the game shows City Walls on the overland map
   (`#20` is the ordinary city, not a walled one; see Progress). The buildings are the 1/0xFF/0 flags from record
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

## Progress (2026-09-23)

- **Checked in DOSBox on SAVE1:** the starting city is drawn as
  `MAPBACK #20` frame 0 with a yellow flag (Freya). Mirror was drawing
  `#21` frame 1; fixed to `#20`, frame `size − 1`. Race (0 Barbarian) and
  population (4 → 4,000) match the record.
- **Game quirk:** loading SAVE1 prompts "Name Starting City" and
  generates a fresh name each time (Deventor became Kufstein). The save's
  stored name isn't what the player sees after loading, so don't use city
  names to cross-check a save against the game.
- **Still to check:** frames for sizes 0 and 2+ (e.g. Steyr, size 2), the
  other banner colours and the neutral browns (those cities are in the fog
  at the start of SAVE1), what `#21` `CITYNOWA` is for, and walls.

