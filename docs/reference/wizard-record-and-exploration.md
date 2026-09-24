# Wizard record and the explored map

Found 2026-09-23 while editing Kevin's "Freya - God mode" save
(`~/DOS/MAGIC/SAVE3.GAM`): fog of war removed, retorts added. Backup of the
saves, before and after the edit: `~/.mirror/dev/DOSbox/FREYA - God Mode/saves-2026-09-23/`.

**Sources:**
- kazzmir's Go remake,
  [kazzmir/master-of-magic](https://github.com/kazzmir/master-of-magic),
  `game/magic/load/load.go` (`loadPlayerData`, `LoadSaveGame`) and
  `convert.go`;
- the bytes of SAVE1, SAVE3 and SAVE9, checked against what the game shows.

Offsets are from the start of a wizard record: `0x9e8 + n × 0x4c8`, where
the player is record 0.

## Wizard record

In the Checked column, "game" means the value matches something the game
shows, and "kazzmir" means the offset comes from kazzmir's read order.

| Offset | Field | Checked |
| --- | --- | --- |
| `+0x00` | portrait / wizard id (u8; Freya = 9) | kazzmir |
| `+0x01` | name, 20 bytes, NUL-padded | game ("Freya") |
| `+0x15` | capital race | kazzmir |
| `+0x16` | banner: 0 blue, 1 green, 2 purple, 3 red, 4 yellow | game (yellow flag, STORY-032) |
| `+0x18` / `+0x1a` | personality / objective (u16, AI) | kazzmir |
| `+0x22` | mastery research (u16) | kazzmir |
| `+0x24` | fame (u16) | game: 10 in SAVE1, which the Famous retort grants |
| `+0x26` | power base (u16) | kazzmir |
| `+0x2a..+0x2c` | research / mana / skill ratio (u8; 34/33/33 in SAVE1) | kazzmir; they sum to 100 |
| `+0x2e` / `+0x30` / `+0x32` | summoning circle x / y / plane (i16) | game: (38, 21, Arcanus), the capital Norport |
| `+0x34` | 8 research candidate spells (u16) | kazzmir; SAVE1's are Nature spell ids |
| `+0x54` / `+0x56` | skill left / nominal skill (u16) | kazzmir |
| `+0x58` | tax rate (u16) | kazzmir |
| `+0x5a` | spellbooks per realm, 5 × i16: **Nature, Sorcery, Chaos, Life, Death** | kazzmir + game (Freya: 12 Nature) |
| `+0x64..+0x75` | **retorts**, one byte each, 1 = has it (table below) | kazzmir + fame check |
| `+0x25c` | mana (u16) | found by value (earlier session) |
| `+0x356` | gold (u16) | found by value (earlier session) |

### Retorts, `+0x64..+0x75`

The byte order is kazzmir's **read** order. His struct declares Node
Mastery before Mana Focusing, but the reader reads Mana Focusing first,
and the file follows the reader.

| Byte | Retort | Byte | Retort |
| --- | --- | --- | --- |
| `+0x64` | Alchemy | `+0x6d` | Myrran |
| `+0x65` | Warlord | `+0x6e` | Archmage |
| `+0x66` | Chaos Mastery | `+0x6f` | Mana Focusing |
| `+0x67` | Nature Mastery | `+0x70` | Node Mastery |
| `+0x68` | Sorcery Mastery | `+0x71` | Famous |
| `+0x69` | Infernal Power | `+0x72` | Runemaster |
| `+0x6a` | Divine Power | `+0x73` | Conjurer |
| `+0x6b` | Sage Master | `+0x74` | Charismatic |
| `+0x6c` | Channeler | `+0x75` | Artificer |

*To confirm in-game:* open the wizard's Info screen in DOSBox and compare
the retorts it lists with these bytes. SAVE3 now has Alchemy, Warlord,
Nature Mastery, Sage Master, Channeler, Myrran, Archmage, Mana Focusing,
Node Mastery, Famous, Runemaster, Conjurer, Charismatic and Artificer.

## Explored map (fog of war)

- **Where:** `0x014814`, 1 byte per tile, row-major 60 × 40. Arcanus
  first (2400 bytes), then Myrror (2400 bytes).
- **Sources for the position:** Mirror's own offset (from the wiki), and
  kazzmir's read order: terrain specials (`0x013554`, 2 × 2400) are
  followed directly by the explored maps.
- **Values:** 0 means unexplored. Otherwise the value is a 4-bit mask,
  and 15 means fully explored.
  - SAVE1 (turn one) has 21 non-zero tiles, 5 of them at 15. These are
    the tiles around the starting city.
  - SAVE9 has 279 non-zero tiles, 195 of them at 15. The rest are 1–14,
    along the edge of the explored area.
  - *Guess:* each bit is one quarter or edge of the tile, drawn with the
    `MAPBACK` edge masks (`#0–#13`). Confirm by setting one tile to 1, 2,
    4 and 8 in turn and looking at it in the game.
- **Which player:** kazzmir treats this as the human player's map (a
  single map per plane); the AI wizards' exploration isn't in this block.
- **Removing the fog:** set all 4800 bytes to 15, as done for SAVE3.
