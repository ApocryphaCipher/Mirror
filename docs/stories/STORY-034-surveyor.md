# STORY-034: Surveyor: what a tile is worth, and what a city there would get

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** in progress: the formula is in Mirror (`Mirror.Surveyor`);
the view-mode readout is next. (Idea from Kevin, 2026-09-23, while
playing through the live-RAM tool.)
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
| Mountain with gold ore, (39, 20) | "Mountain / +5% production", "Gold Ore / +3 gold", then the too-close-to-a-city message. RAM (`cp21_surveyor_gold_ore.bin`): the minerals plane has **4** there, Mirror's value for Gold, so plane and game agree. Its neighbour (38, 19), where a deer is drawn, holds 64 |
| Forest with wild game, (38, 19) | "Forest / 1/2 food / +3% production", "Wild Game / +2 food", then the too-close message. RAM (`cp22_surveyor_wild_game.bin`): minerals plane **64**, Mirror's value for Wild game |
| Desert with gems, (32, 25) | "Desert / +3% production", "Gems / +5 gold", then the too-close message. RAM (`cp23_surveyor_gems.bin`): minerals plane **5**, Mirror's value for Gems |
| **Myrror** hills with Adamantium, (28, 25) | "Hills / 1/2 food / +3% production", "Adamantium Ore / +2 power", then **City Resources: Maximum Pop 17, Prod Bonus +33%, Gold Bonus +10%** (a city is allowed here: the first case of City Resources for an empty site). RAM (`cp24_surveyor_adamantium_myrror.bin`): Myrror minerals plane **7** |
| **Myrror** river mouth with a Keep, (26, 25) | "River Mouth / 1/2 food / +30% gold", "Keep / Unexplored", then "Cities cannot be built on lairs." RAM (`cp25_surveyor_keep.bin`): encounter record 46 at (26, 25, Myrror), kind 7 (Abandoned keep), intact, explored-by flags 0; guards 2 Behemoths + 3 Cockatrices |
| Swamp with Nightshade, (46, 16), beside the neutral city Steyr (47, 16) | "Swamp / 1/2 food", "Nightshade / Protects city from spells", then the too-close message. RAM (`cp32_surveyor_nightshade.bin`): terrain 166, minerals plane **128**, Mirror's value for Nightshade |
| Capua, Sharee's capital (11, 26), a Nomad hamlet of 4,640 | "Forest / 1/2 food / +3% production", "Hamlet of Capua", **City Resources: Maximum Pop 13, Prod Bonus +23%, Gold Bonus +12%**. Its catchment's only special is Silver at (9, 26). RAM (`cp36_surveyor_capua.bin`) |
| Cremona, Merlin's capital (15, 11), a Nomad hamlet of 3,260 on a mountain ring | "Mountain / +5% production", "Hamlet of Cremona", **City Resources: Maximum Pop 8, Prod Bonus +63%, Gold Bonus +9%**. Catchment specials: Coal (15, 10), Gold (16, 11); Nightshade (11, 10) lies just outside. RAM (`cp38_surveyor_cremona.bin`) |
| Sidon, Jafar's capital (55, 29), a Nomad hamlet of 4,640 on a narrow island | "Grasslands / 1 1/2 food", "Hamlet of Sidon", **City Resources: Maximum Pop 14, Prod Bonus +6%, Gold Bonus +12%**. **No specials in the catchment**, so terrain alone gives these: the simplest case for the formula. RAM (`cp39_surveyor_sidon.bin`) |
| Bloodrock, Tlaloc's capital, **Myrror** (54, 23), a Dark Elf (race 2) hamlet of 4,640 on the coast | "Desert / +3% production", "Hamlet of Bloodrock", **City Resources: Maximum Pop 16, Prod Bonus +21%, Gold Bonus +10%**. Catchment special: Gems (54, 21). RAM (`cp40_surveyor_bloodrock.bin`) |
| **Myrror** grassland with a temple, (28, 21) | "Grasslands / 1 1/2 food", "Temple / Unexplored", "Cities cannot be built on lairs." RAM (`cp41_surveyor_temple.bin`): encounter record 74, kind 6 (Ancient temple), intact, flags 0; guards 1 Skeletons + 1 Zombies, 50 mana |

So there are two parts:

1. **The tile itself:** terrain name, its food, and its bonus (and a
   mineral or other special, when there is one).
2. **City Resources:** the maximum population and the production and gold
   bonuses a city on that tile gets from the tiles around it, or the reason
   a city can't go there (too close to another city).

## Where the numbers come from

**City Resources: solved (2026-09-24).** The formula is in
[surveyor-formula.md](../reference/surveyor-formula.md). It was read in
ReMoM, restated in our own words, and implemented in gama (`gama
resources DUMP X Y [PLANE]`). It gives exactly the game's numbers for all
15 full readouts: the six above, and nine more from "Freya - Dior" (edited
city enchantments, and Kevin's survey of road-linked cities). Only shared
tiles' food for an *empty site* is still unchecked.

**In Mirror (2026-09-24):** `Mirror.Surveyor.city_resources/5` ports
gama's rules, and `Mirror.SaveFile.Cities` now decodes building statuses,
city enchantments and road links. Its tests:

- Synthetic worlds built in the test, one rule each.
- The nine Dior readouts, read from a frozen copy of that session's
  `SAVE9.GAM` at `~/.mirror/dev/surveyor-fixtures/` (outside the repo,
  like all game files; the test is skipped without it, or point
  `MIRROR_SURVEYOR_SAVE` at a copy).
- The six older readouts came from RAM dumps rather than saves, so they
  stay checked by gama.

**Next:** the view-mode readout. The hover panel shows the tile lines in
the game's words ("Hills / 1/2 food / +3% production"; swamp says 1/2
food although cities count 0), then City Resources, or why a city can't
be built there. The "less than 3 squares from any other city" distance
rule still has to be checked against the hover log first.

The notes below are from before the formula was found. Candidates were:

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

**City Resources are computed, not stored** (checked on three cities):
no byte of Hamburg's record holds 19, 60 or 50, none of Capua's holds 13
or 23 (its two 12s are the per-turn figures at `+96` and `+100`), and
none of Cremona's holds 8, 63 or 9, and Sidon's only match is a 12 at
`+100` (Capua also has 12 there with +12% gold, but Hamburg's `+100` is
10 against +50%, so it is not the bonus); Bloodrock's holds none of 16,
21 or 10.
So Mirror must compute them from the tiles, like the game.

- **Automatic test cases:** the DOSBox fork's Surveyor watch logs each
  hovered tile's panel text with the tile (see
  [live-ram-map.md](../reference/live-ram-map.md)), so a Surveyor session
  yields hundreds of (tile, text) pairs to check the formula against.

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
