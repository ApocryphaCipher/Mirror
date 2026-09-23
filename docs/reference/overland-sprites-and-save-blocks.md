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

## LBX sprite sources

LBX files carry a readable name table (at file offset `0x200`, 32-byte
rows of `NAME\0` + description). That makes finding sprites far easier
than scanning bytes. What the names show:

### `MAPBACK.LBX` (94 entries): overland map overlays

- `SITES` in `blue` / `green` / `purple` / `red` / `yellow` / `neutral`:
  per-banner-colour pieces. **Most likely the unit plaques** (the coloured
  backing an overland unit figure sits on). Verify.
- `MAPCITY`, `CITYNOWA`: city markers (sizes/owners likely vary by frame).
- `ROADS` in 8 directions (+ `no road`), `E_ROADS`: roads and enchanted roads.
- `MAGIC` in `blue` / `green` / `purple` / `red` / `white` / `yellow`: magic
  overlays by colour. Candidates for **node auras / realm sparkle**, or
  owned-node borders. Verify which.
- `SITES` unowned tower, owned tower, mound, temple, keep, ruins, fallen
  temple: **encounter-zone and tower icons.**
- `SITES` coal, iron, silver, gold, gems, mithril, adamantium, quork,
  crysx, nightshade, wild game, hunter's lodge, mine, lumber camp:
  mineral/special icons.
- `CORRUPT` corruption, `WARPED` warped mask, `MASK` (×16), `MAGIC` city
  worked area.
- The first images are 20×18 (tile-sized).

### `UNITS1.LBX` (120 entries) + `UNITS2.LBX` (78 entries): overland unit figures

All named `STATFIG1` / `STATFIG2`, 18×16 images. Presumably indexed by
unit type number (UNITS1 then UNITS2). Verify the mapping against a known
unit.

### `MAIN.LBX` (65 entries): main-screen UI

Buttons (`MAINBUTN`), movement-type icons (`MAINMOVE` sail/swim/fly/…),
medals, magic-weapon icons, and **`MAINBTN2` "unit backgrnd 1–9"
(entries 24–32, 22×28)**: candidates for the unit plaques in STORY-012,
alongside the `MAPBACK.LBX` `SITES` colour entries. Verify which one the
overland map actually uses.

### `FONTS.LBX` palette entries: mouse cursors

Entries 2–8 (5,472 bytes each) hold a palette followed by 16×16
column-major cursor images (gauntlet, wand, red X, arrow, swords,
hourglass, boot, 5-frame casting sparkle). See STORY-025.

### `TERRAIN.LBX`: animated terrain

79 of the 1524 tile pointers carry the animated flag (4 frames each);
see [classic-terrain-format.md](classic-terrain-format.md). This is where
the **ocean twinkle** comes from, and possibly animated volcano/node tiles.
Which tile numbers they are is not yet listed.

### Image format note

`TERRAIN.LBX` tiles are raw pixels. `MAPBACK`/`UNITS*` entries use the
standard LBX image format (header + RLE frames), which `Mirror.LBX`
already decodes. With the `FONTS.LBX` entry-2 palette forced, they should
render correctly. The 0-index is transparent, which overlays need.
