# STORY-034: Surveyor: what a tile is worth, and what a city there would get

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** open (idea from Kevin, 2026-09-23, while playing through the
live-RAM tool)
**Size:** medium (the display is small; getting the numbers right is the
work)

## The idea

The game has a **Surveyor** mode: hover a tile and the side panel says what
it is and what it's worth. Mirror should have the same readout in view
mode, so you can plan a city site from a save without starting the game.

What the game shows (screenshots in
`~/.mirror/dev/DOSbox/ram-dumps-2026-09-23/surveyor-*.webp`, SAVE3
"God mode" run, turn ~8):

| Tile | Panel |
| --- | --- |
| River, about (37, 22) | "River / 2 food / +20% gold", then "Cities cannot be built less than 3 squares from any other city." |
| Hamburg, (38, 21) | "Hills / 1/2 food / +3% production", "Hamlet of Hamburg", then **City Resources: Maximum Pop 19, Prod Bonus +60%, Gold Bonus +50%** |
| Mountain with gold ore, (39, 20) | "Mountain / +5% production", "Gold Ore / +3 gold", then the too-close-to-a-city message. RAM (`cp21_surveyor_gold_ore.bin`): the minerals plane has **4** there, Mirror's value for Gold, so plane and game agree. Its neighbour (38, 19), where a deer is drawn, holds 64 (*guess:* Wild Game) |

So there are two parts:

1. **The tile itself:** terrain name, its food, and its bonus (and a
   mineral or other special, when there is one).
2. **City Resources:** the maximum population and the production and gold
   bonuses a city on that tile gets from the tiles around it, or the reason
   a city can't go there (too close to another city).

## Where the numbers come from

Nothing here is checked yet. Candidates:

- Tile type: Mirror already reads the terrain (`0x002698`) and minerals
  (`0x013554`) planes, and `TERRAIN.LBX` entry 1 classifies tiles.
- Per-terrain food and bonuses, and the city-resource formula (which
  tiles count, how rivers, shores and specials add up): *guess:* kazzmir's
  remake implements the surveyor; find it and port it with attribution
  (BSD-3), per [kazzmir-save-layouts.md](../reference/kazzmir-save-layouts.md).
- Where a city is allowed: the game's own rule is on screen (not less than
  3 squares from any other city).
- **The game's own wording:** a RAM dump taken with Surveyor open
  (`cp20_surveyor_open.bin`, see
  [live-ram-map.md](../reference/live-ram-map.md)) has the panel's static
  strings in the data segment around `ds+0x5352`: "Surveyor", "Maximum
  Pop", "Prod Bonus", "Gold Bonus", then terrain words ("River", "Hills"
  near `ds+0x5400..0x5490`). The shown text is assembled in a scratch
  buffer near `ds+0xd5a4`. The numbers are not kept as text, so the game
  computes them on hover; Mirror has to compute them too.

## Checking it

Per AGENTS.md §6, the numbers need the game's own confirmation:

- The two rows above are the first test cases: Mirror must show exactly
  "Maximum Pop 19, Prod Bonus +60%, Gold Bonus +50%" for Hamburg's tile in
  that run, and "2 food, +20% gold" for the river tile.
- More cases are cheap: hover tiles in Surveyor mode, screenshot, and
  compare. The live-RAM tool
  ([live-ram-map.md](../reference/live-ram-map.md)) gives each tile's
  exact coordinates and bytes at the same moment.

## Definition of done

View mode has a Surveyor readout for the tile under the pointer, with
both parts, and it matches the game on at least five hovered tiles
(different terrains, a river, a special, a city tile, a too-close tile).
The formula and its source are written into `docs/reference/`.
