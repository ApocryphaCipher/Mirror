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

For an **empty site**, a tile inside **another city's** 21 tiles counts
at half. A city's own tiles always count in full. (*Unchecked:* none of
the six readouts had a shared tile.)

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
| Swamp `A6 B1 B2`, tundra `A7 B5 B6`, volcano `B3` | 0 | 0 |
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

These agree with the tile panel's own text where we have it ("Hills /
1/2 food / +3% production", "Mountain / +5% production", "Grasslands /
1 1/2 food", "River / 2 food").

**Wild game** (special 64) on a worked tile adds food (see Maximum Pop).

## Maximum Pop

- **Existing city:** (half-food ÷ 2, rounded down) + **2 per wild game
  tile** + 2 with a Granary + 3 with a Farmers' Market.
- **Empty site:** (2 × half-food + **1 per wild game tile**) ÷ 4,
  rounded down. The Surveyor counts in quarter food here and adds only a
  quarter food for wild game, although a city built there would get 2.
  **Checked:** the Myrror site's readout (17) is matched this way;
  counting its wild game as for a city gives 19.
- Capped at 25.

*Not covered:* Gaia's Blessing (×1.5 food in ReMoM) and Famine (halves
it) apply to existing cities in ReMoM; none of our cities had them.

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
  half if the same race; *unchecked*, no roads yet). The total so far is
  capped at **3% per thousand people**. Then Merchants' Guild +100,
  Bank +50, Marketplace +50 and Prosperity (slot `0x13`) +100, uncapped.

**Checked:** the cap is visible in the data. Cremona (3,000 people,
coast +10, Nomad +50) shows **+9%**, and Capua and Sidon (4,000, the
same) show **+12%**. Hamburg (5,000, no water or river) shows +50%, all
from its Marketplace.

## The six readouts

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

- Shared tiles (an empty site near another city): the half rule is
  unchecked. One Surveyor hover near a city, with a dump, would settle it.
- Road trade bonus, Gaia's Blessing, Famine, Inspirations, Prosperity:
  none of the six cases had them.
- Corruption: ReMoM's Surveyor loop does not exclude corrupted tiles,
  although a city's real food does. Unchecked.
