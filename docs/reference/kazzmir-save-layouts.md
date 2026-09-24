# Save layouts from kazzmir's remake, checked against our saves

Source: [kazzmir/master-of-magic](https://github.com/kazzmir/master-of-magic),
a Go remake of the game. Read at commit `e824e98` (2026-09-12). BSD-3
licensed, so tables can be ported into Mirror with attribution. The save
loader is `game/magic/load/load.go`, and its meanings are in `convert.go`.

The loader reads `SAVEn.GAM` from start to end, so its read order gives
every block's position independently of the wiki. The wizard record and
the explored map are in
[wizard-record-and-exploration.md](wizard-record-and-exploration.md). This
doc covers the rest of what EPIC-004 and EPIC-006 need.

Each claim is marked with how it was checked:
- **checked**: the save's bytes agree with the game's own data or a
  screenshot (AGENTS.md §6);
- **kazzmir**: from kazzmir's code only; still to check.

The saves are the Freya checkpoints, backed up in
`~/.mirror/dev/DOSbox/FREYA - God Mode/saves-2026-09-23/` (with `MAGIC.SET` and
checksums). The live slots in `~/DOS/MAGIC` will be overwritten. See
[../notes/2026-09-23-evening-handoff.md](../notes/2026-09-23-evening-handoff.md).

**Trust the loader, not the drawing code.** kazzmir's rendering makes
its own choices, and some contradict the real game:
- **City sprite:** he draws `#21` for unwalled and `#20` for walled
  cities. DOSBox shows the game drawing unwalled Ozenwall with `#20`
  (STORY-032).
- **Banner colours:** he recolours by lightening a base colour. The game
  maps flag pixels onto its palette ramps (STORY-032).

Use his *layouts and tables*; check his *pictures* against DOSBox.

## Nodes: `0x006058`, 30 × 48 bytes (STORY-008)

| Offset | Field | Status |
| --- | --- | --- |
| `+0` `+1` `+2` | x, y, plane | **checked:** all 30 land on node tiles in SAVE1 |
| `+3` | owner (i8, −1 = nobody; else wizard index = the melder) | **checked:** all −1 on turn one |
| `+4` | power = number of aura tiles used (SAVE1: 5–20) | kazzmir |
| `+5..+24` | aura tile x's (20 bytes) | **checked:** the first entry is the node's own tile |
| `+25..+44` | aura tile y's (20 bytes) | same |
| `+45` | type: **0 Sorcery, 1 Nature, 2 Chaos** | **checked:** type 0/1/2 nodes stand on terrain tiles 168/169/170 (`0xA8`/`0xA9`/`0xAA`), which kazzmir's terrain table names Sorcery/Nature/Chaos node. 10 of each |
| `+46` | flags (*kazzmir:* warped etc.) | kazzmir |
| `+47` | unknown | — |

**Drawing** (kazzmir; the game is still to check): a node shows aura
sparkles **only when melded**. The sparkle is `MAPBACK #(63 + banner)` of
the owner, drawn on each aura tile. That fits our catalog's sparkle
entries. An unmelded node is just its terrain tile.

## Wizard fortresses: `0x0065f8`, 6 × 4 bytes (STORY-011)

x, y, plane, active. **checked:** records 0–4 are exactly the five
wizards' capitals in SAVE1: Freya (38, 21, Arcanus), Capua (11, 26),
Bloodrock (54, 23, Myrror), Sidon (55, 29), Cremona (15, 11). Record 5
(43, 7, active) is *unexplained*, maybe a slot for the neutral player.

## Towers of Wizardry: `0x006610`, 6 × 4 bytes (STORY-011)

x, y, owner (`0xFF` = none), unknown. **There is no plane byte:** a tower
stands on both planes at once. **checked:** 6 towers, all unowned in
SAVE1. The 4th byte varies (0, 78, 39): *unknown*.

## Encounter zones: `0x006628`, 102 × 24 bytes (STORY-011)

| Offset | Field |
| --- | --- |
| `+0` `+1` `+2` | x, y, plane |
| `+3` | intact (1 = not yet cleared) |
| `+4` | kind (table below) |
| `+5` `+6` | guard 1: unit type, count byte (see below) |
| `+7` `+8` | guard 2: unit type, count byte |
| `+9` | unknown |
| `+10` / `+12` | gold / mana reward (i16) |
| `+14` | spell reward |
| `+15` | flags: *guess:* who has explored the site (see below) |
| `+16` | item count |
| `+17` | unknown |
| `+18` `+20` `+22` | items 1–3 (i16) |

| Kind | Site | Sprite (kazzmir) |
| --- | --- | --- |
| 0 | Tower of Wizardry | `MAPBACK #69` (unowned) / `#70` (owned) |
| 1 / 2 / 3 | Chaos / Nature / Sorcery node guardians | none (the node is a terrain tile) |
| 4 | Cave | `#71` |
| 5 | Dungeon | `#74` |
| 6 | Ancient temple | `#72` |
| 7 | Abandoned keep | `#73` |
| 8 | Monster lair | `#71` |
| 9 | Ruins | `#74` |
| 10 | Fallen temple | `#75` |

**Node guardians, checked in SAVE1.** Every one of the 30 kind-1/2/3
records sits on a node, and the realms match the node record's type byte
all 30 times:

| Encounter kind | Node type byte | Realm |
| --- | --- | --- |
| 1 | 2 | Chaos |
| 2 | 1 | Nature |
| 3 | 0 | Sorcery |

The node's defenders (its "occupying force") live in the encounter
record, not the node record.

**Towers of Wizardry, checked in SAVE1.** A tower's defenders are an
encounter too:
- Records 0–5 are the six towers' Arcanus sides, at exactly the tower
  block's (x, y).
- Records 6–11 are the same towers' Myrror sides: the same (x, y), plane 1,
  and identical guards and rewards.
- Records 99–101 are empty (all zero). That's the wiki's "99 + 3".

That accounts for all 15 kind-0 records: 12 tower sides plus 3 empty
slots. The tower block (`0x006610`) holds only the tower itself (x, y,
owner), and the encounter holds the guards. SAVE1's guards are all
summoned creatures, e.g. tower (33, 7): Unicorns ×3 and Guardian Spirits
×4, plus 10 gold and 30 mana.

*To check:*
- Clear one side of a tower, then diff the two records. Does the game
  update both (one tower, two records) or only the side you entered?
- There's no link field between the tower and the encounter; they match
  only by position.

**Guard count byte: two packed nibbles.** kazzmir uses only the low
nibble (`count & 0xF`). In SAVE1 all 148 filled guard slots have the high
nibble equal to the low one (`0x11`, `0x22` … `0x88`).
- **checked (live RAM, 2026-09-23):** the **low nibble is the guards
  left, the high nibble the starting count**. After Kevin's Sprites beat
  all eight Phantom Warriors at the Sorcery node (42, 10), encounter 19's
  count went `0x88` → `0x80`, and intact `+3` went 1 → 0
  ([live-ram-map.md](live-ram-map.md)). A retreat mid-fight would show a
  partial low nibble; not seen yet.

**`+15` flags: *guess*, who has explored the site.** kazzmir leaves it
unread (`ExploredBy: // FIXME`).

| Save | What changed in `+15` |
| --- | --- |
| SAVE1 | 94 sites are 0. Five are `0x01`, spread over both planes (records 14, 23, 33, 43, 57); what that bit means is unknown |
| SAVE7–9 | Sites Freya came near change 0 → `0x02` (records 19, 54, 71, 83) |
| SAVE7–9 | The fallen temple at (32, 28) (record 65) goes to `0x06` |

- Records 71 and 83 (a cave and a dungeon, neither with guards) also flip
  `intact` 1 → 0. Freya presumably looted them.
- *To check:* did Freya enter the fallen temple at (32, 28)? And what
  sets bit `0x01`?

The sprite column is kazzmir's choice. It settles our catalog's guess
that `#71` "mound" is a cave or lair.

## Units: `0x00b734`, up to 1009 × 32 bytes, count u16 at `0x0009e2` (STORY-012)

| Offset | Field |
| --- | --- |
| `+0` `+1` `+2` | x, y, plane |
| `+3` | owner (wizard 0–4, 5 = neutral) |
| `+4` | max moves |
| `+5` | **unit type** (u8) |
| `+6` | hero slot |
| `+7` | finished (done this turn) |
| `+8` | moves left |
| `+9` `+10` | destination x, y |
| `+11` | status |
| `+12` | level |
| `+13` | unknown |
| `+14` | experience (i16) |
| `+16` | move failed |
| `+17` | damage |
| `+18` | draw priority |
| `+19` | in tower (i16) |
| `+21` | sight range |
| `+22` | mutations |
| `+23` | enchantments (u32 bitmask) |
| `+27` `+28` `+29` | road building: turns, x, y |

**Checked in SAVE1:**
- 42 units: 2 per wizard, 32 neutral city garrisons.
- Freya's two are at Norport (38, 21), types **39 Barbarian Spearmen** and
  **40 Barbarian Swordsmen**, which fits her Barbarian capital.

**Unit type** (`getUnitType` in `convert.go`): 0–34 are the 35 heroes
(0 Brax, 1 Gunther, 2 Zaldron … 34 Torin). Then 35 Trireme, 36 Galley,
37 Catapult, 38 Warship, and the racial units from 39, followed by the
summoned creatures. This agrees with our catalog's figure sprites:
`UNITS1 #type` for types 0–119 and `UNITS2 #(type − 120)` for the rest.

## Minerals map: `0x013554`, 2 × 2400 bytes (STORY-013)

One byte per tile, row-major.

| Value | Special | Sprite |
| --- | --- | --- |
| 1 | Iron ore | `MAPBACK #78` |
| 2 | Coal | `#79` |
| 3 | Silver | `#80` |
| 4 | Gold | `#81` |
| 5 | Gems | `#82` |
| 6 | Mithril | `#83` |
| 7 | Adamantium | `#84` |
| 8 | Quork crystals | `#85` |
| 9 | Crysx crystals | `#86` |
| 64 | Wild game | `#92` |
| 128 | Nightshade | `#91` |

**checked in the running game** (live RAM + Surveyor, 2026-09-23, dumps
`cp21`/`cp22` in [live-ram-map.md](live-ram-map.md)): **4** at (39, 20),
where Surveyor said "Gold Ore +3 gold", and **64** at (38, 19), where it
said "Wild Game +2 food"; **5** at (32, 25), where it said "Gems +5 gold"
(`cp23`); and on **Myrror (the second plane)**, **7** at (28, 25), where it
said "Adamantium Ore +2 power" (`cp24`; the tile was pinned by its
neighbours: 64 at (27, 26) and (24, 23), 4 at (28, 29), 7 at (26, 29),
all visible on screen).

- **Checked:** every value in SAVE1 is 0 or one of those 11.
- **Checked, and a correction:** `#78` is iron and `#79` is coal.
  - The pictures: `#78` is rust-red, `#79` black.
  - MAPBACK's name table has the two swapped, and so did our catalog
    until this doc.
- *Still to check in-game:* that value 1 (iron) really sits on the tiles
  where DOSBox shows iron.

## Terrain flags: `0x01cbb8`, 2 × 2400 bytes (STORY-013, 018)

One byte per tile, row-major.

| Bit | Meaning | Status |
| --- | --- | --- |
| `0x08` | road | **checked** (details below) |
| `0x10` | enchanted road | **checked:** in SAVE1 only Myrror tiles have it (13), because Myrror's roads start enchanted. On Arcanus the **Enchant Road** spell sets it, so it can appear on either plane. *To check:* cast Enchant Road on Arcanus (STORY-032 checkpoint 7) and diff the flags |
| `0x20` | corruption | kazzmir; none in SAVE1–9 |

How the road bit was checked:
- Its tiles run Speger (34, 16) → Ozenwall (31, 20) → Posen (31, 24).
  That's the brown road in the 4:37:49 PM DOSBox shot.
- City tiles have it too: Norport (38, 21) always, and Zwolle (35, 26)
  from the save where it was founded.

The other bits aren't in kazzmir's converter; SAVE1–9 set only
`0x08`/`0x10`.

**Road pieces** (kazzmir; they match our catalog):
- Draw `MAPBACK #45 + d` (`#54 + d` for enchanted roads) for each
  neighbour with a road. `d` is 1 N, 2 NE, 3 E, 4 SE, 5 S, 6 SW, 7 W,
  8 NW.
- A road tile with no road neighbours gets `#45` (`#54`) alone.

## Terrain tile table (STORY-017)

`game/magic/terrain/terrain.go` lists every `TERRAIN.LBX` tile, Arcanus
`0x000..` and Myrror from `0x2FA`. For each tile it gives:
- its terrain type (ocean, shore, grass, forest, river, node…);
- for each of its 8 sides, the terrains that may sit next to it
  (`makeDirections` bit order: W, SW, S, SE, E, NE, N, NW).

That's the auto-tiling rule STORY-017 needs. Porting the table (with
attribution) may replace decoding `TERRTYPE.LBX`. *To check:* redraw
SAVE1 from the table's terrain types and compare tile for tile with the
save's u16s.

## Block offsets (backlog: "sanity-check the wiki offsets")

The loader reads every block in file order, so adding up its read sizes
gives each block's offset without the wiki. **checked:** the explored map
lands at `0x014814`, straight after the two minerals planes. The same sum
can confirm the terrain (`0x002698`), landmass (`0x004d98`) and flags
(`0x01cbb8`) offsets in `scripts/dev_server.sh`. *Not done yet.*
