# EPIC-011: Artifacts

**Status:** proposed (2026-10-12), nothing built
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
- **Unknown:** the item record layout (name, type, picture, cost, the power list and each power's value), where a hero's
  slots and a wizard's vault live in the save, how the game checks an item's powers (the Artificer's Create Artifact
  rules: realm books, cost) and whether it checks them on load at all. Start from kazzmir's loader and the
  `ITEM*`/`ITEMDATA` LBX files; confirm with a diff of a save before and after Kevin equips or creates one.

## Stories

- [STORY-054](../stories/STORY-054-artifact-decode.md): decode the item record and where items live (hero slots, vault, lairs)
- [STORY-055](../stories/STORY-055-artifacts-view.md): show artifacts: on a hero, on the wizard page, in a lair panel
- [STORY-056](../stories/STORY-056-artifacts-editing.md): edit, move and create artifacts

Related: [EPIC-010](EPIC-010-heroes.md) (who carries them), [EPIC-009](EPIC-009-wizard-editing.md) (the wizard's vault).
