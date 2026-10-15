# STORY-054: Decode artifacts

**Parent:** [EPIC-011](../epics/EPIC-011-artifacts.md)
**Status:** mostly done (2026-10-15): `Mirror.SaveFile.Items` decodes the item block, a hero's and a vault's items; a lair's `+18..+22` turned out not to be item indexes. The power names are read by `Mirror.ItemPowers` (`ITEMPOW.LBX` is in the manifest, without a hash). Not done: the premade-table tail and a check against the game's own screen. *Original note:* open (2026-10-12). The item block is located and its record read (see below); the codes are not mapped.
**Size:** large
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-12

## What to do

**Found (2026-10-12):** the 138 × 50-byte item block at `0x6fb8`, the hero and vault item indexes, and the game's own `ITEMDATA.LBX` and `ITEMPOW.LBX` (see [wizard-heroes-diplomacy-items.md](../reference/wizard-heroes-diplomacy-items.md)). Left to do, with two sources each:

- the **item record**: name, type (sword, staff, ring...), picture, cost, and the list of powers with each one's value;
- where items live: a **hero's equipment slots**, a **wizard's vault** of spare items, and a **lair's reward items**
  (the encounter record's item area, `+16` onwards, whose ids are not decoded);
- the **power table** (which powers exist and how they are numbered), from the game's own data files if they hold it
  (the `ITEM*` LBX files, not in the manifest yet; adding one is a `Mirror.GameFiles.manifest/0` change and needs Kevin's say-so).

Method: kazzmir's loader, then a before-and-after diff in the real game (equip an item, create one with Create Artifact, take
one from a lair) read through the DOSBox fork. Mark every guess as a guess.

## Definition of done

`docs/reference/` has the layout; a decoder in `Mirror.SaveFile` returns the items of a real save and agrees with what
the game shows for at least one hero and one lair.

## Built (2026-10-15)

`Mirror.SaveFile.Items`: `parse/1` (the items in use), `get/2`, `for_indexes/2`, `vault/2`, `type_name/1`, `slot_name/1`. The record layout and the type and slot codes are the ones
already written in [wizard-heroes-diplomacy-items.md](../reference/wizard-heroes-diplomacy-items.md) (checked against `ITEMMAKE.EXE` on 14 premade items); a free slot is a record with an
empty name. Read on `SAVE2.GAM` (no game session): five items, and Sir Harold's two (Mae Govannon, Plate of Enduring Immunity) and Jafar's vault item (Protection of Ramses) resolve to
real items with sensible type and slot names.

**Found on the way: a lair's three numbers are not item indexes, and (checked in the game, 2026-10-15) they do not set the quality of the reward.** The encounter record's `+18`, `+20`, `+22` hold 360 up to 2400 in 22 saves, never a position in the item block. In the game an item came with the value at 0, 100, 9000 and 30000 (costs 800, 600, 1250, 1550). The **count at `+16`** is how many items the game makes; see [the findings](../reference/wizard-heroes-diplomacy-items.md#findings-2026-10-15-lairs-new-items-and-the-premade-table-real-game). The lair panel now edits that count and no longer calls the numbers items.

Also found there: the premade "in play" table in the last 810 bytes of the save, and where the game puts a new item (first unreferenced record, plus a working copy in record 136).

Open: the **power names** (`ITEMPOW.LBX` is not in `Mirror.GameFiles.manifest/0`; adding it needs Kevin's say-so, so `abilities` stays a mask for now), the 6-byte tail of a premade record,
how many items a hero may hold at once (three entries in the list), and a comparison with the game's own item screens.
