# Overland sprites and save blocks: what's where

Survey done 2026-09-22 to scope EPIC-004 and EPIC-005. It records **where
things live**; most per-record layouts still need verifying (marked below).
Sources: the GOG release's LBX files (Google Drive, "Master of Magic
Official Release"), and the
[Save Game Format wiki](https://masterofmagic.fandom.com/wiki/Save_Game_Format)'s
top-level block table.

## Save-file blocks (offsets from the wiki's top-level table)

| Block | Offset | Record size | Count | Record layout known? |
| --- | --- | --- | --- | --- |
| Wizards (+ neutral) | `0x0009e8` | `0x04c8` | 5 + 1 | Yes (wiki). **Banner colour at `+0x16`** (`0` blue, `1` green, `2` purple, `3` red, `4` yellow) |
| Node attributes | `0x006058` | `0x30` (48) | 30 | **No.** Expected to include x/y/plane, owner, realm, and the list of aura tiles; verify |
| Fortresses | `0x0065f8` | 4 | 6 | No. Probably x/y/plane/active per wizard; verify |
| Towers of Wizardry | `0x006610` | 4 | 6 | No. Probably x/y/owner; verify |
| Encounter zones | `0x006628` | `0x18` (24) | 99 + 3 | **No.** Lairs, ruins, temples, keeps, mounds, etc. Needs type + x/y/plane + guardians |
| Cities | `0x008aac` | `0x72` (114) | 100 | Mostly: momedit gives race/x/y/plane/owner/pop (see [momedit-source](momedit-source/)) |
| Units | `0x00b734` | `0x20` (32) | 1000 + 9 | **No.** Needs x/y/plane/owner/unit type at minimum. Unit count at `0x0009e2` |
| Terrain flags map | `0x01cbb8` | 1 / tile | 2 × 2400 | No. Likely roads / enchanted roads / corruption bits; verify |
| Minerals map | `0x013554` | 1 / tile | 2 × 2400 | No. Mineral/special type per tile; verify |

Verifying a layout means using two sources, or one source plus a visual
check against a known save, as was done for the terrain offsets.

## Sprite catalog (verified 2026-09-23, STORY-006)

Every entry below was decoded with `Mirror.LBX` and **looked at**. Contact
sheets were rendered with the game palette, and the same decode was checked
against an independent Python decoder: 1,380 frames hash-identical across
MAPBACK, UNITS1/2, MAIN, SPECFX, MAGIC and CITYSCAP. Browse any of these in
`/tile-probe`, which now shows the name table next to each entry.

Notation: `FILE.LBX #entry[/frame]`, 0-based, numbered from the offset table
at byte 8, the same numbering the name table uses. Rows marked *guess* are
reasoned from the pictures, not yet confirmed against a save.

### Cities: `MAPBACK.LBX` #20, #21 (32×30, 5 frames)

| Sprite | Entry |
| --- | --- |
| City **with** walls, size 1–5 | `MAPBACK.LBX #20/0..4` (`MAPCITY`) |
| City **without** walls, size 1–5 | `MAPBACK.LBX #21/0..4` (`CITYNOWA`) |

Frames grow from a single hut (frame 0) to a sprawling capital (frame 4).
*Guess:* frame = the game's city size class (hamlet … capital); confirm
against a save's city population in STORY-010. The frame-0 wall ring is
what tells #20 from #21. The owner flag is 8 px in palette indices
**216–218** (the green ramp; x 17–20, y 10–11 in frame 0). *Guess:* the
game swaps those three indices for the owner's banner ramp (see the
sparkle ramps below).

### Unit plaques: `MAPBACK.LBX` #14–#19 (20×18)

Tile-sized, filled, dark-bordered squares, one per banner colour. The unit
figure sits on top.

| Banner (wizard record `+0x16`) | Entry |
| --- | --- |
| 0 blue | `MAPBACK.LBX #14` (`SITES blue`) |
| 1 green | `MAPBACK.LBX #15` |
| 2 purple | `MAPBACK.LBX #16` |
| 3 red | `MAPBACK.LBX #17` |
| 4 yellow | `MAPBACK.LBX #18` |
| neutral / raiders | `MAPBACK.LBX #19` (brown) |

`MAIN.LBX #24–#32` (`MAINBTN2 unit backgrnd 1–9`, 22×28) are **not** the
map plaques. They are grey stone buttons with a health-bar slot, used by
the unit panel on the main screen's right side.

### Unit figures: `UNITS1.LBX` / `UNITS2.LBX` (18×16, 1 frame, all `STATFIG*`)

| Unit type | Entry |
| --- | --- |
| 0–119 | `UNITS1.LBX #type` |
| 120–197 | `UNITS2.LBX #(type − 120)` |

Checked against the game's unit list by eye. UNITS1 #0–34 are 35 mounted
heroes, then #35 trireme, #36 galley, #37 catapult, #38 warship, and
settler wagons appear among the racial units (e.g. #44). UNITS2 #34–#77
are the 44 summoned creatures in the known order: #34 magic spirit, #35
hell hounds, #36 gargoyles, #37 fire giant, #38 fire elemental … #70
floating island, #71 phantom beast, #72 phantom warriors, #73 storm giant,
#74 air elemental, #75 djinn, #76 sky drake, #77 nagas. That is unit type
154–197, which makes the offset of 120 exact. Still to do: confirm against
a save's unit records (STORY-012).

### Encounter sites and towers: `MAPBACK.LBX` (20×18, 1 frame)

| Sprite | Entry |
| --- | --- |
| Tower of Wizardry, unowned | `MAPBACK.LBX #69` |
| Tower of Wizardry, owned | `MAPBACK.LBX #70` |
| Mound (*guess:* cave / monster lair) | `MAPBACK.LBX #71` |
| Temple | `MAPBACK.LBX #72` |
| Keep | `MAPBACK.LBX #73` |
| Ruins | `MAPBACK.LBX #74` |
| Fallen temple | `MAPBACK.LBX #75` |
| Mud (brown speckle; *guess:* a terrain special, not a site) | `MAPBACK.LBX #76` |

Nodes are terrain tiles (`TERRAIN.LBX`), not sprites. Which encounter-zone
type number uses which icon is STORY-011's job.

### Specials (minerals, food): `MAPBACK.LBX` (20×18, 1 frame)

| Special | Entry |
| --- | --- |
| Coal | `#78` |
| Iron | `#79` |
| Silver | `#80` |
| Gold | `#81` |
| Gems | `#82` |
| Mithril | `#83` |
| Adamantium | `#84` |
| Quork crystals | `#85` |
| Crysx crystals | `#86` |
| Nightshade | `#91` |
| Wild game | `#92` |
| Mine, lumber camp, hunter's lodge | `#87`, `#88`, `#90`: **blank** (47-byte entries, every column empty) |

The minerals-map byte → special mapping is STORY-013's job.

### Roads: `MAPBACK.LBX` (20×18)

Each piece is the half-road from the tile centre toward one neighbour.
Draw the pieces for every connected neighbour, plus the centre piece.

| Piece | Normal road (1 frame) | Enchanted road (6-frame animation) |
| --- | --- | --- |
| centre ("no road") | `#45` | `#54` |
| top | `#46` | `#55` |
| top right | `#47` | `#56` |
| right | `#48` | `#57` |
| bottom right | `#49` | `#58` |
| bottom | `#50` | `#59` |
| bottom left | `#51` | `#60` |
| left | `#52` | `#61` |
| top left | `#53` | `#62` |

The `E_ROADS` rows have no descriptions in the name table. Their order was
read off the pictures and matches `ROADS` exactly.

### Sparkles / node auras: `MAPBACK.LBX` #63–#68 (20×18, 6 frames)

Twinkling star sparkles, one colour each. The name table says blue, green,
purple, red, white, yellow, but the pixels say otherwise:

| Colour actually drawn (palette indices) | Entry | Name-table label |
| --- | --- | --- |
| blue (219–220, 100) | `#63` | blue |
| green (216, 218) | `#64` | green |
| purple (121–124) | `#65` | purple |
| red (200–203) | `#66` | red |
| **yellow** (211–212) | `#67` | "white" |
| **nothing** (every frame blank) | `#68` | "yellow" |

So sparkle = `MAPBACK.LBX #(63 + banner)` for banners 0–4. *Guess:* these
are the melded-node aura sparkles in the owner's colour (STORY-008). Verify
against a save with a melded node.

### Other `MAPBACK.LBX` entries

| Sprite | Entry |
| --- | --- |
| Edge masks, black dither along one or two sides (*guess:* unexplored-area edges) | `#0–#13` (`MASK`, 20×18) |
| Corruption | `#77` (22×18: note the width) |
| City worked-area outline (blue dashed border, 6 frames) | `#89` (`MAGIC city worked area`) |
| Warped mask (black blob) | `#93` |
| (empty entries, 0 bytes, no name) | `#22–#44` |

### Other files

- `MAIN.LBX` (65 entries): main-screen UI. Buttons, `MAINMOVE` movement
  icons (#18–23, #36–38), medals (#51–53), magic-weapon icons (#54–56),
  the unit-panel stone buttons above.
- `FONTS.LBX` #2–#8 (5,472 bytes each): a palette followed by 16×16
  column-major cursor images (see STORY-025). #2's first 768 bytes are the
  game palette.
- `TERRAIN.LBX`: terrain tiles, not in the standard image format; see
  [classic-terrain-format.md](classic-terrain-format.md).

## LBX formats (as implemented in `Mirror.LBX`)

**Container.** `u16 count`, `u16 0xFEAD`, 4 bytes, then `count + 1` u32
entry offsets from byte 8. Most files also have a **name table** at `0x200`:
one 32-byte row per entry, a 9-byte NUL-padded name then a NUL-terminated
description (`SITES` / `blue`). The sound banks and `TERRAIN.LBX` have none
(56 of the 61 GOG files do). Before this story, `Mirror.LBX` guessed the
table position and accepted a table at byte 4 whenever bytes 4–7 were zero.
That shifted every entry index by one in files like `MAPBACK.LBX`.
`TERRAIN.LBX` and `FONTS.LBX` happened to parse correctly, so "entry 2" and
TerrainLbx's entries 1/2 were right all along.

**Images.** Header `u16 width, height, 0, frames, delay, ?, ?,
palette_info, flags`, then `frames + 1` u32 frame offsets at `0x12`. Each
frame starts with a byte: `1` = fresh, `0` = drawn over the previous frame.
Then comes one record per column, left to right: `0xFF` = empty column,
else a mode byte (`0x00` copy, `0x80` RLE), a size byte and `size` bytes of
runs. Each run is `count, skip`, then `count` encoded bytes placed `skip`
rows below the previous run's end. In RLE mode a byte `b > 0xDF` means
"repeat the next byte `b − 0xDF` times". All 3,543 image entries in the 61
GOG LBX files on disk decode with this.

**Palette.** `FONTS.LBX` #2, first 768 bytes, 6-bit VGA (× 255/63). Index 0
is transparent. When `palette_info` is non-zero, it points at `u16 offset,
first, count`, a 6-bit patch over colours `first…` (e.g. `MAGIC.LBX #0`
patches 224–255). 355 image entries carry one, mostly full-screen art.

**The old "colored noise" bug** was the decoder, not the palette. The old
code read `frames` from offset 4 (always 0), so every real image failed the
header check. It then fell back to painting the RLE bytes as raw pixels,
which is the noise. Forcing the FONTS palette alone changed nothing: with
the old decoder every MAPBACK entry still failed. Separately, it wrote
pixels as BGRA into a canvas that expects RGBA, swapping red and blue.
Fixed in STORY-006.
