# The save file mapped onto RAM, from the game's own writes

Source: the DOSBox fork's DOS file-call log (`webserver_file_log`) for
Kevin's session of 2026-09-24 ("Freya - Gawdess"). Every time the game
saves, it writes each block of `SAVEn.GAM` straight from where the block
lives in memory, so each write names a file offset, a length and a RAM
address. This is the game's own account, not a match or a guess. The log
is in the Evi vault (collection `mom-live-2026-09-24`); `gama filemap
files.jsonl --file 'SAVE*.GAM' --op write` reproduces the table.

**Checked:** 34 writes cover all 123,300 bytes, and the 13 saves made by
`WIZARDS.EXE` in that session (9 automatic to `SAVE9.GAM`, 4 to slot 4)
used identical addresses. Every block we had placed by hand
([live-ram-map.md](live-ram-map.md)) lands where we said.

## How a game starts: two programs

`MAGIC.EXE` (the menu) loads the chosen slot (here `SAVE3.GAM`), writes it
to **`SAVE9.GAM`** (the "continue" slot), and starts **`WIZARDS.EXE`**,
which loads `SAVE9.GAM`. `WIZARDS.EXE` then rewrites `SAVE9.GAM` at every
turn. The addresses below are `WIZARDS.EXE`'s; the menu's copy of the
game sat about 0x835A bytes lower, which is why only `WIZARDS.EXE`'s
addresses held across launches. `MAGIC.SET` holds the slot names ("Freya -
Gawdess" is slot 4).

## The map

RAM addresses are physical, in DOSBox with the default 16 MB. "RAM − file"
is constant within a block.

| Save offset | Bytes | RAM | What |
| --- | --- | --- | --- |
| `0x0000` | 6 × 420 | `0x07D570`, `0x07D750`, `0x07D920`, `0x07DAF0`, `0x07DCC0`, `0x07DE90` | **Heroes, one block per player** (420 = 35 heroes × 12 bytes). In RAM they are 6 separate buffers, `0x1E0` then `0x1D0` apart, which is why matching the save never found them |
| `0x09D8` | 8 × 2 | `0x03478C` down to `0x03477E` | 8 u16 counters in the data segment, written one by one in reverse address order; `0x09E2` is the unit count (`0x034782`), `0x09E0` *guess:* the city count |
| `0x09E8` | 7344 | `0x0328BA` | **Wizard records** (5 × 0x4C8 = 6120) and what follows them to `0x2698` |
| `0x2698` | 9600 | `0x072630` | Terrain, 2 planes × 2400 × u16 |
| `0x4C18` | 192 | `0x074BE0` | unknown (two 192-byte blocks, 0x30 apart in RAM) |
| `0x4CD8` | 192 | `0x074CD0` | unknown |
| `0x4D98` | 4800 | `0x074DC0` | Landmass, 2 × 2400 |
| `0x6058` | 1440 | `0x085FE0` | Nodes, 30 × 48 (the live copy; the one at `0x087010` is stale) |
| `0x65F8` | 24 | `0x0865C0` | Wizard fortresses, 6 × 4 |
| `0x6610` | 24 | `0x086610` | Towers of Wizardry, 6 × 4 |
| `0x6628` | 2448 | `0x086660` | Encounter zones, 102 × 24 |
| `0x6FB8` | 6900 | `0x087F70` | *guess:* items, 138 × 50 (kazzmir's size) |
| `0x8AAC` | 11400 | `0x06F980` | Cities, 100 × 114 |
| `0xB734` | 32288 | `0x07E060` | Units, 1009 × 32 |
| `0x13554` | 4800 | `0x0760B0` | Minerals, 2 × 2400 |
| `0x14814` | 4800 | `0x078690` | **Explored map**, 2 × 2400 |
| `0x15AD4` | 28800 | `0x0E27B0` | *guess:* movement costs (28,800 = 6 × 2 × 2400) |
| `0x1CB54` | 100 | `0x087C70` | unknown |
| `0x1CBB8` | 4800 | `0x0773A0` | Terrain flags, 2 × 2400 |
| `0x1DE78` | 2 | `0x032712` | a u16 in the data segment |
| `0x1DE7A` | 250 | `0x089AA0` | unknown |
| `0x1DF74` | 560 | `0x087D00` | unknown |

## What the session's actions showed (SAVE3 → SAVE4)

Diffing the save Kevin started from (`SAVE3`, "God mode") with the one he
ended with (`SAVE4`, "Gawdess"):

- **Summoning circle:** wizard `+0x2E/+0x30/+0x32` moved from (38, 21, 0),
  the capital, to (42, 16, 0), his city Rostock, after he cast Summoning
  Circle there. **Checked** by the action.
- **City enchantment:** the capital (renamed Soest in this run) got
  **slot 14 = 1** in its 26-byte enchantment block (`+0x43`, i.e.
  `+67..+92`). ReMoM names slot `0x0E` `Natures_Eye`; the value 1 fits
  "player index + 1". The block is the city enchantments, **checked**.
- **Transmute:** minerals at (39, 20) and (36, 23) went 4 → 1 (Gold →
  Iron), so **1 = Iron** is checked by a spell whose effect is known.
- **Change Terrain:** 20 Arcanus tiles changed around the capital.
