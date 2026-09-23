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

## Debug save and checkpoints

`~/DOS/MAGIC/SAVE3.GAM` ("Freya - God mode" in the Load menu) is SAVE1
with 30,000 gold and 30,000 mana (wizard 0 `+0x356` / `+0x25c`). Play it
in DOSBox, and at each checkpoint save to a spare slot **and** take a
screenshot of the overland map around the city. Then Mirror can compare
the save's bytes with what the game drew. Record each result here.

| # | Checkpoint | What it settles |
| --- | --- | --- |
| 1 | Starting city at pop 5K (Village) | frame for size 2 (Mirror assumes frame 1) |
| 2 | Buy **City Walls** | how walls look on the overland map; which building flag (record `+34…`) is City Walls |
| 3 | Pop 9K, 13K, 17K+ (Town, City, Capital) | frames 2–4 and the size byte for each |
| 4 | Found a new city with Settlers (pop 1K) | the smallest size byte and its frame |
| 5 | Meet each rival wizard's city (explore, or cast a detection spell) | flag colours for red, purple, blue, green |
| 6 | See a neutral city (e.g. Steyr, 47, 16, size 2) | neutral flag colour; a size-2 frame from the start |
| 7 | Build a road; cast **Enchant Road** | road pieces and animated enchanted roads (STORY-013) |
| 8 | Visit a tower, a lair or ruins, and a node | site icons (STORY-011) and node auras (STORY-008) |
| 9 | Units standing on the map, own and enemy | unit figures and banner plaques (STORY-012) |
| 10 | Anything showing `MAPBACK #21` (`CITYNOWA`) | what that sprite is for |

