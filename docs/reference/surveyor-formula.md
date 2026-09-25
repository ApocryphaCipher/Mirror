# The Surveyor's City Resources formula

The Surveyor panel shows **Maximum Pop, Prod Bonus and Gold Bonus** for
the hovered tile: for an empty tile, what a city built there would get;
for a city, what it gets now. These numbers are computed on hover and
never stored (STORY-034 checked five city records for them). This page
states the rules in our own words.

**Source:** the rules were read in ReMoM
([remom.md](remom.md); `jbalcomb/ReMoM` commit `a9cc082`: the functions
`Compute_Base_Values_For_Map_Square`, `City_Maximum_Size`,
`City_Food_Terrain`, `Square_Food_x2`, `Square_Production_Bonus` and
`City_Road_Trade_Bonus` in `MoM/src/CITYCALC.c`, and `Square_Gold_Bonus`,
`Square_Is_River` and `Square_Is_Sailable` in `MoM/src/Terrain.c`). ReMoM
has no licence, so nothing here is copied from it: the tables below are
restated facts, and the code is our own.

**Implementation:** gama's `src/gama/resources.py` (`gama resources DUMP X
Y [PLANE]`).

**Checked** on all six readouts recorded on screen (below), using the RAM
dump taken while each was shown. Where our result differed from a literal
reading of ReMoM, the game's numbers decided; see "Where ReMoM misleads".

## The inputs

All from RAM ([live-ram-map.md](live-ram-map.md)); the same blocks are
in the save file ([save-to-ram-map.md](save-to-ram-map.md)).

- **Terrain** (`0x72630`, u16 per tile). A tile's kind is the value
  mod 762; higher values are animation frames of the same tile.
- **Specials** (minerals plane, `0x760B0`): here only 64 = wild game
  matters.
- **Explored map** (`0x78690`): 0 = unexplored.
- **Cities** (`0x6F980`, 114 bytes each): position `+15..+17`, race
  `+14`, population in thousands `+20`, built flags `+31+id` (1 built,
  0 replaced by a better building, `0xFF` not built), enchantments `+67`
  (26 slots), road links `+101` (13 bytes, one bit per city index).

## Which tiles count

A city works the **21 tiles** of the 5 × 5 square around it, less the
four corners. x wraps around at 60, and rows off the top or bottom of the
map are dropped. **Unexplored tiles are skipped.**

A tile that **another city** also works is **shared**:

- **Production:** a shared tile gives half its production, rounded down
  per tile (a mountain 5 → 2, a forest 3 → 1), for a city and an empty
  site alike. **Checked** on Steyr: three tiles shared with Bremen take
  45% down to the **37%** the game shows. The same rule then gave Bremen's
  +76% with no further change.
- **Food:** a shared tile gives half its food, and the total is rounded
  only after summing. **Checked** for cities: Straatus, Blade Stone and
  Ozenwall (Kevin's road survey, below) match only this way, and Steyr
  rules out rounding each tile. Empty sites use the same halving in gama.
  *Unchecked* for empty sites.
- **Wild game** on a shared tile gives a city 1, not 2 (ReMoM).
  *Unchecked.*

## Food and production per tile

Food is counted in **half-food units** (grassland 3 = 1½ food).
Production is the bonus in %.

| Tile (kind) | Half-food | Production % |
| --- | --- | --- |
| Ocean `0x00`, tundra and animated ocean `≥ 0x259` | 0 | 0 |
| `0x01` | 3 | 0 |
| Shores `0x02..0xA1` | 1 | 0 |
| Grassland `A2 AC AD B4` | 3 | 0 |
| Forest `A3 B7 B8` | 1 | 3 |
| Mountain `A4` | 0 | 5 |
| Desert `A5` | 0 | 0 |
| Desert `AE AF B0` | 0 | 3 |
| Swamp `A6 B1 B2` (the panel says ½ food; see below) | 0 | 0 |
| Tundra `A7 B5 B6`, volcano `B3` | 0 | 0 |
| Sorcery node `A8` | 4 | 0 |
| Nature node `A9` | 5 | 3 |
| Chaos node `AA` | 0 | 5 |
| Hills `AB` | 1 | 3 |
| Rivers, lakes, inland shores `0xB9..0x102` | 4 | 0 |
| Mountain ranges `0x103..0x112` | 0 | 5 |
| Hill ranges `0x113..0x123` | 1 | 3 |
| Desert ranges `0x124..0x1C3` | 0 | 3 |
| Shores `0x1C4..0x1D3` | 1 | 0 |
| Four-way rivers `0x1D4..0x1D8` | 4 | 0 |
| Shores `0x1D9..0x258` | 1 | 0 |

**Checked against the tile panel.** `gama surveyor hits.jsonl --check
SAVE9.GAM` compares each logged hover's food and production text with
this table. Of 180 hovers, 65 agree (49 distinct tiles: forest, hills,
mountains, desert, grassland, shore, river, swamp and a nature node), 106
carry no food or production text, and 9 conflict. Every conflict is text
left over from the tile hovered just before, or from a map jump. The
panel pads halves with spaces ("1   1/2 food").

**Swamp is the one difference, and it's the game's own:** the panel says
"Swamp / 1/2 food", but cities count swamp as **0** food. Ebonsway (four
swamp tiles) shows Maximum Pop 9; at ½ food it would be 11. ReMoM notes
the manual's ½ against the code's 0.

**Wild game** (special 64) on a worked tile adds food (see Maximum Pop).

## Maximum Pop

- **Existing city:** its tiles' half-food, less **corrupted** tiles
  (terrain flag `0x20`; unexplored tiles count here), **× 1.5 with
  Gaia's Blessing** (slot `0x11`, rounded down), then ÷ 2 rounded down;
  **halved by Famine** (slot `0x07`, rounded down); then + **2 per wild
  game tile** + 2 with a Granary + 3 with a Farmers' Market. A Granary
  that has been **replaced** (built flag 0) still counts.
- **Empty site:** (2 × half-food + **1 per wild game tile**) ÷ 4,
  rounded down. The Surveyor counts in quarter food here and adds only a
  quarter food for wild game, although a city built there would get 2.
  **Checked:** the Myrror site's readout (17) is matched this way;
  counting its wild game as for a city gives 19.
- Capped at 25.

**Checked** by editing the save (below): Gaia's Blessing took Sidon from
14 to **21** (29 half-food × 1.5 = 43 → 21). Famine took Steyr from 15 to
**8** (26 → 13 → 6, + Granary 2). Konstanz, whose Granary is replaced by a
Farmers' Market, shows **22** (15 + 2 + 3 + wild game 2).

## Prod Bonus

The sum of the worked tiles' production %. A city adds: Sawmill +25,
Forester's Guild +25, Miners' Guild +50, Mechanicians' Guild +50, and
Inspirations (enchantment slot `0x12`) +100.

## Gold Bonus

- **The tile itself:** +20% if it is a river (kinds `0xB9..0xC4`,
  `0xE9..0x102`, `0x1D4..0x1D8`), and +10% if any of its 8 neighbours is
  water: ocean or shore (kinds `≤ 0xA1` except `0x01`, `0x1C4..0x1D3`,
  `0x1D9..0x25A`) or a lake (`0xC5..0xE8`). Both together give +30%.
  The neighbours count even when unexplored.
- **A city** then adds +50% if Nomad (race 11), plus the **road trade
  bonus** (each city joined by road adds its population in thousands,
  half if the same race). The total so far is
  capped at **3% per thousand people**. Then Merchants' Guild +100,
  Bank +50, Marketplace +50 and Prosperity (slot `0x13`) +100, uncapped.

**Checked:** the cap is visible in the data. Cremona (3,000 people,
coast +10, Nomad +50) shows **+9%**, and Capua and Sidon (4,000, the
same) show **+12%**. Hamburg (5,000, no water or river) shows +50%, all
from its Marketplace.

**Road trade, checked below the cap:** Blade Stone (Myrror, 4,000 people,
no water) is joined to Straatus (another race, 4,000: +4) and Ebonsway
(the same race, 3,000: +3 ÷ 2 = 1) and shows **+5%**. Ozenwall (9,000,
coast +10) is joined to Posen (the same race, 4,000: 2) and Speger (3,000:
1) and shows **+13%**. Each linked city's half is rounded down on its own.
Steyr (7,000, river +20, roads +12) shows the cap, **+21%**.

## The readouts

| Tile | Dump | Game | Formula | Detail |
| --- | --- | --- | --- | --- |
| Hamburg (38, 21) | `cp20_surveyor_open` | 19, +60%, +50% | same | 31 half-food → 15, wild game +2, Granary +2; 9 mountains, 3 hills, 2 forests = 60%; Marketplace |
| Capua (11, 26) | `cp36_surveyor_capua` | 13, +23%, +12% | same | 27 → 13; coast + Nomad capped at 4 × 3 |
| Cremona (15, 11) | `cp38_surveyor_cremona` | 8, +63%, +9% | same | 17 → 8; coast + Nomad capped at 3 × 3 |
| Sidon (55, 29) | `cp39_surveyor_sidon` | 14, +6%, +12% | same | 29 → 14; capped at 4 × 3 |
| Bloodrock (54, 23, Myrror) | `cp40_surveyor_bloodrock` | 16, +21%, +10% | same | 32 → 16; Dark Elf, coast only |
| Empty site (28, 25, Myrror) | `cp24_surveyor_adamantium_myrror` | 17, +33%, +10% | same | (2 × 34 + 1) ÷ 4; coast |

Dumps are in `~/.mirror/dev/DOSbox/ram-dumps-2026-09-23/` and the Evi
vault (collection `mom-live-2026-09-23`).

**Kevin's road survey** (2026-09-24, "Freya - Dior", screenshots; checked
with `gama resources SAVE9.GAM X Y P`). These are road-linked neutral
cities, several of which share tiles with a neighbour:

| City | Game | Formula | What it tests |
| --- | --- | --- | --- |
| Straatus (39, 6, Myrror) | 14, +11%, +12% | same | shared food (16 if counted in full); roads capped at 4 × 3 |
| Blade Stone (40, 10, Myrror) | 19, +50%, +5% | same | shared food (21 in full); road trade below the cap |
| Ebonsway (48, 11, Myrror) | 9, +13%, +9% | same | swamp counts 0 food |
| Posen (31, 24) | 7, +35%, +12% | same | roads capped |
| Ozenwall (31, 20) | 13, +29%, +13% | same | shared food (14 in full); road trade below the cap |
| Speger (34, 16) | 10, +29%, +9% | same | roads capped |

With the edited cities below, **all 15 full readouts match**.

## Editing the save to test enchantments (2026-09-24)

No city had a city enchantment, so we wrote them into "Freya - Dior"
(`SAVE5.GAM`). The enchantment slot's value is the caster's player
index + 1. We predicted the readouts with `gama resources SAVE5.GAM X Y`
(committed before loading), then Kevin loaded the save and hovered.

| City | Edit | Predicted | Game |
| --- | --- | --- | --- |
| Konstanz (38, 21) | Inspirations, Prosperity, Earth Gate, Nature Ward | 22, +160%, +150% | **same** |
| Sidon (55, 29), Jafar's | Gaia's Blessing | 21, +6%, +12% | **same** |
| Steyr (47, 16) | Famine (as if cast by Sharee), Stream of Life | 8, +45%, +21% | 8, **+37%**, +21% |
| Bremen (51, 16), not edited | none | +76%, +15% (after the shared-tile fix) | "+76%", "15%" (from the hover log; max pop not captured) |

Steyr's miss is what found the shared-tile rule above. Everything else
matched first time. The edits also stuck in the game: the city screens
list the enchantments (the hover log caught "Do you wish to turn off the
Prosperity / Nature Ward / Stream of Life spell?"). The same edit made
Freya's 22 "knowable" Nature spells (status 1) known (2). Her spell
library is 214 bytes at wizard `+0x264` (spell *n* at byte *n* − 1; 0
unknown, 1 knowable, 2 known, 3 researchable). The research list (`+0x34`,
8 spells) and current research (`+0x262`) were left alone.

The original save, the edited copy and the edit script are in
`~/.mirror/dev/DOSbox/save-edits-2026-09-24/`.

## Where ReMoM misleads

A literal reading of ReMoM's Surveyor routine gives wrong numbers in two
places. Both are most likely slips in the reconstruction, and the game's
numbers above settle them:

- The gold cap is written as population **÷ 3**; the readouts need
  population **× 3** (ReMoM's own road trade function uses × 3).
- In the tile loop, the unshared branch **assigns** each tile's food to
  the total instead of adding it, and the shared branch does the same
  for production, unit cost, gold and power. Adding is what matches.

One real quirk of the game is flagged in ReMoM as an original bug: an
empty site's wild game adds 2 quarter-food instead of 8. The Myrror
readout confirms that the game really does this. Hamburg's readout
(19, not 17) confirms that an existing city gets the full 2 food.

## Still open

- Shared food for an empty site, and shared wild game: unchecked. One
  Surveyor hover on an empty tile beside a city would settle the first
  (`gama resources` on the save gives the prediction).
- Corruption: ReMoM's Surveyor loop does not exclude corrupted tiles,
  although a city's real food does. Unchecked.
