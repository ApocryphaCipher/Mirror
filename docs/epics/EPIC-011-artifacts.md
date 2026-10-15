# EPIC-011: Artifacts

**Status:** in progress (2026-10-15): STORY-054 mostly done (decoder, power names); STORY-055 built and checked in the game (the wizard page shows hero items and the vault); STORY-056 first slice built and checked in the game (edit an item in place), move built and checked in the game, fill from the premade table and remove built and checked in the game
**Owner:** [Kevin](https://github.com/KevinAsbury)
**Requested:** 2026-10-12, split out of EPIC-009 (wizard editing): artifacts (magic items) get their own epic.

## The idea

Show every artifact in the save (a hero's equipment, a wizard's stored items, items waiting in a lair), and edit them:
rename, change the powers, move one from a hero to a wizard's vault or to another hero, and create one from scratch.
Lair panels already show "N items" and cannot edit them (STORY-020: "the items (ids not decoded)").

## What is known, and what is not

- **Known:** a lair's encounter record has an item count (`+16`) and an item area after it; clearing a lair can
  roll an item into the record (a Chain Mail and a Sword were seen as rewards, 2026-10-12); the game ships item data
  files that are not in Mirror's manifest (the small `ITEM*` LBX files are on Kevin's Drive, `docs/backlog.md`).
- **Found (2026-10-12), [wizard-heroes-diplomacy-items.md](../reference/wizard-heroes-diplomacy-items.md):** **the save has an item block of 138 records of 50 bytes at `0x6fb8`**, between the encounters and the cities (the sum checks); every item index in the save points into it. A record has the name, icon, slot, type, cost, eight stat bytes, charges and an ability mask. A hero's three items are at `+0x76 + 28n + 16`, a wizard's four vault items at `+0x120`. Checked on SAVE2: Sir Harold's item and Jafar's vault item read as real items with matching stats. **The "artifact database" is also in the game folder:** `ITEMDATA.LBX` (250 premade items), `ITEMPOW.LBX` (67 item powers) and `ITEMS.LBX`/`ITEMISC.LBX` (the art), which `ITEMMAKE.EXE`, the Create Artifact screen, reads.
- **Checked in `ITEMMAKE.EXE` (Kevin, 2026-10-12):** its Item #1 is the first `ITEMDATA` record (Black Asp, sword, +1 Attack, Resist Elements, cost 250), so the item record, the type codes (the program's ten tabs in order), the slot codes, the stat bytes, the charged-spell encoding and the ability mask (the OR of the powers' masks) are confirmed, on 14 items across all ten types.
- **Unknown:** what the 6-byte tail of a premade record means (it looks like book requirements) and the other ability bits, how a free item slot is marked, how an item is made from powers (the Create Artifact cost and book rules, which `ITEMMAKE.EXE` enforces) and whether the game checks an item on load at all.

## Stories

- [STORY-054](../stories/STORY-054-artifact-decode.md): decode the item record and where items live (hero slots, vault, lairs)
- [STORY-055](../stories/STORY-055-artifacts-view.md): show artifacts: on a hero, on the wizard page, in a lair panel
- [STORY-056](../stories/STORY-056-artifacts-editing.md): edit, move and create artifacts

Related: [EPIC-010](EPIC-010-heroes.md) (who carries them), [EPIC-009](EPIC-009-wizard-editing.md) (the wizard's vault).
