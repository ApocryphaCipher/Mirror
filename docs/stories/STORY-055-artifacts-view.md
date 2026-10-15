# STORY-055: Show artifacts

**Parent:** [EPIC-011](../epics/EPIC-011-artifacts.md)
**Status:** mostly built (2026-10-15): items are shown in words on each hero and in a vault list on `/wizard/:id`, and the lair panel no longer calls its numbers items; not done: the units panel rows, a hero page, powers' amounts, the check against the game's own item screen. *Original note:* open (2026-10-12), after STORY-054
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
