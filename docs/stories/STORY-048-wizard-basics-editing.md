# STORY-048: Edit a wizard's gold, mana, fame, name, books and retorts

**Parent:** [EPIC-009](../epics/EPIC-009-wizard-editing.md)
**Status:** open (2026-10-12), after STORY-047
**Size:** medium
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-12

## What to do

In edit mode the wizard page gets a form for the fields whose offsets are already checked:

- **Gold** (`+0x356`, u16) and **mana** (`+0x25c`, u16): whole numbers from 0 to **30000**, the game's own cap
  ([uge-mom-model.md](../reference/uge-mom-model.md); in [live-ram-map.md](../reference/live-ram-map.md) a value above it went back to
  30000 by the next screen). 65535 is only the u16 storage range: check what the game does with a value between 30001 and 65535
  in a loaded save before allowing it.
- **Fame** (`+0x24`, u16).
- **Name** (`+0x01`, 20 bytes NUL-padded): printable ASCII only, as for city names (the game's font has no accented
  letters, 2026-10-11); length limit 19 plus the NUL (*check*; city names are 13).
- **Books** (`+0x5a`, 5 × i16): 0 to 13 per realm (*guess* on the top, the game's own limit has to be tested; Kevin's
  Jafar has 12 Sorcery books and the game took it).
- **Retorts** (`+0x64..+0x75`, 18 × u8): tick boxes; the game's rules about which combinations are allowed (a wizard
  with Myrran, Archmage and so on) are not enforced by the save, so the page warns where it knows the rule and does not
  block.

**Derived values stay the game's:** power base (`+0x26`), casting skill and the research candidates are recomputed by the game
(Kevin's Jafar showed "Power Base: 12" until the game was loaded and recomputed it, 2026-10-10). The page shows them and says
so. *Open:* which of them does the game recompute on load and which at End Turn; read it back after each.

One apply is one undo step. Changing the name also changes what every map panel shows for that owner.

## Definition of done

- Each field loads in the real game with the game's screens agreeing (Magic and Info screens), and survives one End Turn; read
  back from memory (`scripts/verify_loaded_save.py`) and a vault checkpoint recorded in this story.
- Unit tests for `Structures.edit_wizard/3` (or the module it lands in) and LiveView tests for the form, refusing bad values
  and saying why.
