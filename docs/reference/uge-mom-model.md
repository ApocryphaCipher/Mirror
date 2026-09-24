# The UGE model of `SAVEn.GAM` (December 2000)

An independent, 25-year-old field map of the save file, found in Kevin's
game archive: `~/DOS/MagicExtras/UGE Templates/MOM.mdl`, a model for the
DOS hex editor UGE (`UGE.EXE`, with `GAMEDAT.UGE` pointing it at
`SAVE3.GAM`). The same folder has `SPELLS.MDL` (a model of the spell data)
and `MagicExtras/Hacking NFO/` (old notes on buildings, items, saves,
spells and the wizards in the EXE), not yet read.

It counts as a separate source under AGENTS.md §6: where it agrees with
a field we checked in the running game, that field has two sources.

## Format

136 entries of 26 bytes: a length byte, a 20-byte name buffer (only the
first *length* bytes count; the rest is leftover text), the field's
**absolute save-file offset** as a u32, and a type byte (`0x0b` string,
`0xfe` u16, `0xfd` u16 with a range in the name, `0xff` byte).

## What it says, against what we know

Offsets below are wizard-record-relative (`0x9e8 + n × 0x4c8`, see
[wizard-record-and-exploration.md](wizard-record-and-exploration.md)).

| UGE name | Offset | Agrees with |
| --- | --- | --- |
| Wizard's Name | `+0x01` | checked (game) |
| Fame | `+0x24` | checked (live RAM: +1 fame after a battle) |
| Nature, Sorcery, Chaos, Life, Death | `+0x5a..+0x62` | kazzmir + game (Freya: 12 Nature) |
| Retorts: Chaos Mastery `+0x66`, Sorcery Mastery `+0x6a`, Myrran `+0x6d`, Mana Focusing `+0x6f`, Artificer `+0x75` (others unnamed) | `+0x64..+0x75` | Mirror's retort table (kazzmir order) for Chaos Mastery; check the others against it |
| Mana (0–30000) | `+0x25c` | checked (live RAM) |
| Gold (0–30000) | `+0x356` | checked (live RAM) |
| Town 1…54 | save `0x8aac`, 114 bytes apart | checked: the city block |

**New leads** (one source only; still to check):

- **Heroes:** 6 slots of 28 bytes at `+0x78`, one per hired hero (UGE
  shows the name). This is likely the per-wizard hero list we couldn't
  find in RAM.
- **Spell table:** 214 bytes from `+0x264`, one per spell: Nature from
  `+0x264` ("0 Earth to Mud"), Sorcery `+0x28c`, Chaos `+0x2b4`, Life
  `+0x2dc`, Death `+0x304` (40 each), then Arcane `+0x32c`, Spell of
  Mastery `+0x338`, Spell of Return `+0x339`. *guess:* each byte is that
  spell's status (unknown / researchable / known). It sits right after
  the research spell at `+0x262`; Earth Lore is spell 10 there, which
  would be table index 9 if the ids are 1-based.
- "84 Corruption" is marked on some rival wizards (`+0x2ab` and `+0x2b7`),
  i.e. individual spell bytes the author was editing.
- The "0–30000" ranges on mana and gold fit the cap seen in the game
  (Freya's gold and mana stayed at 30,000).
