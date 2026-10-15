# STORY-055: Show artifacts

**Parent:** [EPIC-011](../epics/EPIC-011-artifacts.md)
**Status:** built and checked in the real game (2026-10-15): items are shown in words on each hero and in a vault list on `/wizard/:id`, and the lair panel no longer calls its numbers items; not done: the units panel rows, a hero page, powers' amounts, a check of lair rewards. *Original note:* open (2026-10-12), after STORY-054
**Size:** medium

## What to do

Show items in words: a hero's equipment on his row and on the wizard page, the wizard's vault, and a lair's reward items in
the lair panel (which now says only "N items"). Each item: name, type, powers with values, and where it is. View mode too.

## Definition of done

The names and powers agree with the game's own item screen for the same items in a real save; tests on a synthetic save.

## Built (2026-10-15)

`MirrorWeb.ItemPanel.describe/3` puts an item in words (type, cost, stat bonuses, the special powers from `ITEMPOW.LBX`, the charged spell with its charges); `/wizard/:id` shows each hero's
items under his row and a **Vault** section. Without `ITEMPOW.LBX` the stats still show and the powers are flagged ("names need ITEMPOW.LBX"), not guessed.

Seen on SAVE2 through the panel (no game session): Sir Harold carries Mae Govannon (Sword, +1 Attack, +1 Defense, +5 Spell Skill, Lightning) and Plate of Enduring Immunity
(+4 Defense, +2 Movement, Magic Immunity, Endurance); Jafar's vault holds Protection of Ramses (+6 Defense, +4 Movement, Cloak of Fear, Endurance).

- **Movement is stored in half points in a save** (*inferred*): those three items have 4, 8 and (Shield of Eros) 2 in the save and 2, 4 and 1 in the premade table, every other byte equal. The page halves it.
  Confirm on the game's own item screen. The stat byte order (attack, to hit, defense, movement, resistance, spell skill, spell save) is confirmed against the premade table:
  "Chain Mail of Movement" and "Shield of Speed" have only the fourth byte set, "Amulet of Resistance" the fifth.
- **The lair panel's "items" were not items** (see STORY-054): it now reads "1 item to roll (value 360, a guess)".
- Not done: hero rows on the units panel, the power amounts ("+3 Defense" as a power is the stat byte), the comparison with the game's item screen.

## Checked in the real game (2026-10-15)

SAVE2 loaded from Load Game in the research DOSBox (writes on; nothing was written to the game or saved); the game's memory held the same item block as the file (`0x87F70`, 6900
bytes, identical). The **Armies > Items** screen and each item's info (right-click) read, against what `/wizard/1` shows:

| Item | Game's info | Mirror |
| --- | --- | --- |
| Mae Govannon (Sir Harold, sword) | +1 Attack, +1 Defense, +5 Spell Skill, Lightning (armor piercing) | same |
| Plate of Enduring Immunity (Sir Harold) | +4 Defense, +2 Movement, Endurance, Magic Immunity | same |
| Protection of Ramses (Jafar's vault) | +6 Defense, +4 Movement, Cloak of Fear, Endurance | same |

So **the half-point movement is confirmed** (bytes 4 and 8 show as +2 and +4), the stat byte order is right for these items, and the power names from `ITEMPOW.LBX` are the game's.
The Items screen also showed Sir Harold with his sword, his plate and an empty third slot, and the vault with the one shield, as Mirror lists them. Evidence in the Evi vault,
collection `mom-live-2026-10-15`: checkpoints 110 (Ramses), 111 (plate) and 112 (sword), each with a screenshot.

Not checked: an item with a charged spell, "Spell Save", "To Hit" or "Resistance" bytes (none of these three has them), a lair's reward after clearing.
