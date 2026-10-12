# Wizard record, second half: heroes, vault, diplomacy, global enchantments; and the item block

Found 2026-10-12 while asking where the game keeps its artifact database (Kevin: the DOS game ships a separate
artifact-maker, `ITEMMAKE.EXE`). Feeds EPIC-009 (wizard page), EPIC-010 (heroes) and EPIC-011 (artifacts).

**Sources:**
- kazzmir's Go remake, [`game/magic/load/load.go`](https://github.com/kazzmir/master-of-magic/blob/master/game/magic/load/load.go)
  (`loadPlayerData`, `loadPlayerHeroData`, `loadDiplomacy`, `loadItems`, read order and field sizes). Offsets below are the
  running sum of his read sizes, which is how the first half of the record was placed and **checked** (research points at
  `+0x25a`, gold at `+0x356` agree with it).
- Kevin's played game (`SAVE2.GAM`), read 2026-10-12: every layout below produced sensible values (the checks are named per row).
- The game's own files in `~/DOS/MAGIC` (not committed): `ITEMDATA.LBX`, `ITEMPOW.LBX`, `ITEMS.LBX`, `ITEMISC.LBX`, `HERODATA.LBX`,
  `ITEMMAKE.EXE`, and the shipped manual of the old DOS editor, `MMOMS.TXT` (MoM Multiplayer Shell), whose editor screens
  (`MAPEDIT7.COM`) show what the community could edit in 1995.

Offsets are from the start of a wizard record, `0x9e8 + n × 0x4c8`; continues
[wizard-record-and-exploration.md](wizard-record-and-exploration.md).

## In the wizard record

| Offset | Field | Checked |
| --- | --- | --- |
| `+0x76` | **hero list**: 6 entries of 28 bytes: unit index (i16, −1 none), name (14 bytes, NUL-padded, the hero's own given name), 3 item indexes (i16, −1 none) into the item block below, 3 item slot types (i16) | **SAVE2:** Jafar's entry 0 is unit 51 "Sir Harold", and unit 51 is a Sir Harold at his capital; Freya's is unit 137 "Rockfist"; the item index 1 is a sword; slot types (1, 5, 6) |
| `+0x11e` | 2 unknown bytes | kazzmir |
| `+0x120` | **vault**: 4 item indexes (i16, −1 empty): the wizard's spare items | **SAVE2:** Jafar's vault holds item 2, "Protection of Ramses"; the others have none |
| `+0x128` | **diplomacy**, 306 bytes, six entries per array (players 0 to 4 and 5 = neutral); layout below | **SAVE2:** see below |
| `+0x25a` | research points left (u16) | already checked |
| `+0x356` | gold (u16) | already checked: 8293 on the map screen = the record |
| `+0x358` | unknown (u16) | kazzmir |
| `+0x35a` | astrology: magic power, spell research, army strength (3 × i16, the Astrology screen's three bars) | kazzmir; *guess:* values not read |
| `+0x360` | population (u16) | **SAVE2:** 4, 0, 0, 0, 1 for the five wizards: fits a count the game keeps, *meaning unchecked* |
| `+0x362` | "historian" series, 288 bytes (the Historian screen's graph) | kazzmir |
| `+0x482` | **global enchantments: 24 bytes**, one per global spell, the active ones non-zero (*guess:* 0/1; the caster is the record they sit in) | **order from `MMOMS.TXT` appendix A.3:** the same 24, Eternal Night first. **SAVE2 has none active**, so the encoding has not been seen non-zero |
| `+0x49a` | magic strategy (u16), unknown (u16), then 6 × u16 "hostility" | kazzmir; *guess:* AI hostility toward each player; SAVE2 values are small (Jafar's are 0,0,0,0,2,3) |

### Diplomacy block (306 bytes at `+0x128`), field offsets inside it

Each entry is by *other player* 0 to 5 (the record owner's own slot is 0 or unused).

| In block | Field | Size |
| --- | --- | --- |
| `+0` | contacted | 6 × i8 |
| `+6` | treaty interest, `+18` peace interest, `+30` trade interest | 6 × i16 each |
| `+42` | **visible relations** (the figure the Diplomacy screen shows) | 6 × i8 |
| `+48` | **diplomacy status** (*guess, ReMoM's names:* 0 none, 1 wizard pact, 2 alliance, 3 war, 4 final war) | 6 × i8 |
| `+54` | strength | 6 × i16 |
| `+66` | action, `+72` spell (i16 × 6), `+84` city | |
| `+90` | **default relations** | 6 × i8 |
| `+96` | contact progress, `+102` broken treaty | 6 × i8 |
| `+108` | unknown | 6 × i16 |
| `+120` | **hidden relations** | 6 × i8 |
| `+126` | unknown (24), `+150` tribute spell (6 × i8), `+156` unknown (90), `+246` tribute gold (6 × i16), `+258` unknown (30), `+288` and `+294` unknown (6 each), `+300` warning progress (6 × i8) | |

**SAVE2:** the values are small signed numbers in the range seen in the game (relations from −81 to +15), the contact flags
match who has met whom, and the status byte is 2 for Freya toward Sharee and Tauron (and Sharee's and Tauron's toward Freya), and 3 for Jafar and for
Tauron toward the neutral side (war with the raiders is the natural reading). That fits the names above, but **no status has been changed in the game
yet**, so the code's meaning is a *guess*.

## The item block: `0x6fb8`, 138 × 50 bytes

Right after the encounters (`0x6628 + 102 × 24`) and right before the cities (`0x8aac`), so the sum checks: `0x6fb8 + 138 × 50 = 0x8aac`.
Item indexes everywhere in the save (a hero's three, the vault's four, a lair's `+18..+22`) are positions in this array.

| In record | Field |
| --- | --- |
| `+0` | name (30 bytes, NUL-padded) |
| `+30` | icon (u16, an entry of `ITEMS.LBX`) |
| `+32` | slot, `+33` type (kazzmir's names; the codes are not mapped) |
| `+34` | cost (u16) |
| `+36..+43` | attack, to hit, defense, movement, resistance, spell skill, spell save, spell (8 × u8) |
| `+44` | charges (u16) |
| `+46` | abilities (u32 bit mask) |

**SAVE2:** index 1 is "Mae Govannon" (cost 1200, +1 to hit) and index 2 "Protection of Ramses" (cost 2100, +6 defense, +8 resistance,
a sword and a shield by name), the two items the heroes and the vault point at. A save always has 138 slots; how a slot is marked
free is not yet read.

## The game's own artifact data

`ITEMMAKE.EXE` is the Create Artifact screen, a separate program the game runs. It reads:
- **`ITEMDATA.LBX`**: one entry, 250 records of 56 bytes: the 250 **premade items** (name in the first 30 bytes, then
  numbers). The save has a 250-byte table of "premade items still available" right after the heroes block (kazzmir
  `loadPremadeItems`, *guess:* 0 or 1 each).
- **`ITEMPOW.LBX`**: one entry, 67 records of 30 bytes: the **item powers** ("+1 Attack" to "Spell Charges"), a name (22
  bytes) and eight numbers (a kind, a realm for the spell-like ones, an amount, and bit masks that look like the `abilities` bits
  above). The meaning of each number is not read yet.
- **`ITEMS.LBX`** (116 pictures) and **`ITEMISC.LBX`** (36): the item art.

The 250 premade names and the 67 powers are game data and stay out of the repository; the decoder will read them from
`MIRROR_MOM_PATH`.

## What the old DOS editor's screens tell us

`MMOMS.TXT` ships with the game folder (the community "MoM Multiplayer Shell" editor; `MAPEDIT7.COM` is its editor).
Its editor screens show what its author found editable in 1995, which is a map for ours:
- **Wizard:** gold, mana, fame, skill, race, the five book counts, the retorts ("skills"), every spell as *not known /
  known / unchangeable (in the research book) / researchable*, and **"globals" yes/no**: so the global enchantments are plain
  per-wizard flags, as above. Spells are numbered 0 to 239 in the realm order Nature, Sorcery, Chaos, Life, Death, Arcane
  (40 each; Arcane uses 200 to 213); the 24 globals are numbered 0 to 23. The manual lists both (appendix A.2 and A.3).
- **Lair, tower or node:** two guard units (type and number), and a treasure screen with **gold, mana, prisoner (yes/no), "magic"
  (none, common spell, uncommon spell, rare spell, very rare spell, 1 retort or spellbook pick, 2 retort or spellbook picks),
  the number of magic items, and an "item chance, out of 16"**. That is seven values for the seven treasure codes (0 to 6) in the
  lair record's `+14`, which was our open question in STORY-020. It is a *lead, not a decode*: our own experiments (2026-10-12) did
  not match it cleanly (code 5 gave a Chain Mail and a Disjunction spell, not a retort or a book), so it needs a retest. The
  "prisoner" and "item chance" fields would be the two bytes still unknown in the record (`+9` and `+17`, which are 0 in every one
  of 1,713 lair records here).
- **City:** owner, race, population. **Units:** edit units in a city. **Structures:** select and move (we did these too).
- There is **no diplomacy editor** in it: relations and treaties are new ground.
