# STORY-054: Decode artifacts

**Parent:** [EPIC-011](../epics/EPIC-011-artifacts.md)
**Status:** open (2026-10-12). The item block is located and its record read (see below); the codes are not mapped.
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
