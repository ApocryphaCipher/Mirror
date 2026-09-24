# ReMoM: a reassembly of Master of Magic 1.31

[jbalcomb/ReMoM](https://github.com/jbalcomb/ReMoM) rebuilds Master of
Magic v1.31 in C from the original executable, with the game's data
structures named field by field (`MoX/src/MOM_DAT.h`) and its game logic
as functions (for example `MoM/src/CITYCALC.c`, the city calculations).
It is active (last push 2026-08-31, commit `a9cc082`, snapshotted in the
private Evi vault as collection `remom-a9cc082`).

**Licence: none.** Read it and cite it (file, struct, field name,
offset); never copy its code into Mirror or our tools. Reimplement from
the understanding, with a citation.

It counts as an independent source (AGENTS.md §6): it comes from the
executable's code, where our other sources are the save file, RAM, the
screen and old hacking notes.

## Where it agrees with what we checked

Offsets are record-relative and match the save file.

- **Wizard (`struct s_WIZARD`, 0x4C8 bytes):** name `+0x01`, banner
  `+0x16`, fame `+0x24`, power base `+0x26`, research/mana/skill ratios
  `+0x2A..+0x2C` (settling the order), skill left `+0x54`, nominal skill
  `+0x56`, research cost remaining `+0x25A`, mana `+0x25C`, spell being
  researched `+0x262`, gold `+0x356`.
- **City (`struct s_CITY`, 114 bytes):** population `+0x14`, `Pop_10s`
  `+0x18`, construction `+0x1C`, building status from `+0x1F` (building
  *n* at `+0x1F+n`), production `+0x5D`, stored production `+0x5E`,
  gold `+0x60`.
- **Lair (`struct s_LAIR`, 24 bytes) and node (`struct s_NODE`, 48
  bytes):** every field we checked, including the guard-count nibbles
  (the game copies the low nibble into the high one at new game).

## What it adds (one source: still to check in the game)

- **Wizard:** `+0x4C` combat skill left (**checked since**: 61 then 55
  on the combat screen), `+0x25E` casting skill as a **32-bit** value,
  heroes at `+0x76` (6 × 28 bytes), diplomacy at `+0x128` (our unknown
  running totals at `+0x130..+0x14F` sit inside it), the spell library
  at `+0x264`, history from `+0x362`, the 18 retorts `+0x64..+0x75` by
  name (alchemy, warlord, chaos mastery, nature mastery, sorcery mastery,
  infernal power, divine power, sage master, channeler, myrran, archmage,
  mana focusing, node mastery, famous, runemaster, conjurer,
  charismatic, artificer).
- **City:** `+0x1E` building count (our unknown `+30`: it went 3 → 4
  when the Granary was built), `+0x43` the 26 city enchantments (our
  guessed block, now checked; ReMoM marks the last slot, `+0x5C`, as
  Nightshade, but the game never set it, even for a city of Kevin's with
  Nightshade in reach: see [live-ram-map.md](live-ram-map.md)), `+0x61` building maintenance, `+0x62`
  mana, `+0x63` research, `+0x64` food per turn, `+0x1A` contacts.
- **The Surveyor formula** (STORY-034) should be in `CITYCALC.c`.
