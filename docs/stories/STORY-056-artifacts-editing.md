# STORY-056: Edit, move and create artifacts

**Parent:** [EPIC-011](../epics/EPIC-011-artifacts.md)
**Status:** first slice built and checked in the real game (2026-10-15): an item can be edited in place (name, cost, stats, special powers) from the wizard page, loaded and kept through one End Turn; move, create, remove and a lair's reward are not built. *Original note:* open (2026-10-12), after STORY-055
**Size:** large

## What to do

- Rename an item; change its powers and values; **move** it between a hero's slots, a wizard's vault and another hero;
  **create** one from a type and a power list; remove one; set a lair's reward items.
- The Artificer rules (a Create Artifact needs the realm's books and a mana cost) are the game's to enforce in play; the editor
  may build any item, with a warning where a rule is known. *Open:* whether the game rejects, repairs or accepts an item whose
  powers do not fit its type; find out with one deliberately odd item in a test slot and say what happened.

## Definition of done

One of each edit (rename, change a power, move, create) loaded in the real game, seen on its item screen and surviving one End
Turn; tests as in STORY-048.

## First slice built (2026-10-15): edit an item in place

In edit mode every item on `/wizard/:id` (a hero's, the vault's) has a small form: **name**, **cost**, the stats (attack, to hit, defense, **movement as the screen shows it**, resistance,
spell skill, spell save) and a **checkbox per special power** (from `ITEMPOW.LBX`; hidden without it). `Structures.edit_item/3` writes the bytes, one undo step per apply. It edits the
item wherever it is held, so an item a wizard does not hold cannot be changed from his page.

- **Limits are the Create Artifact screen's own** (the premade table's maxima, and the power table's amounts): name 1 to 26 ASCII characters, attack 0-6, to hit 0-3, defense 0-6, movement 0-4
  (stored 0-8, half points: see STORY-055), resistance 0-6, spell skill 0-20, spell save 0-4, cost 0 to 65535. Sums above what the screen can build are refused, not clamped.
- The stat powers ("+3 Defense") are the stat bytes, so they are edited as numbers; **only the special powers are boxes**. Ability bits that no power owns are kept as they are.
- The charged spell, its charges, the icon, slot and type are not edited.
- **Checked in the real game (2026-10-15)**, see below: rename, change of stats and added powers load, show on the item screen and survive one End Turn, **including a power that does not fit the type**.

Not built: **move** (between a hero's three slots, the vault and another hero: the list entries and their slot types), **create** (a free item slot: the game's rule for a free slot is unknown, an empty name is
what Mirror reads), **remove**, and a lair's reward items (a lair holds no item before it is cleared: STORY-054).

## Real-game check of the first slice (2026-10-15)

Test save: `SAVE2.GAM` with two items edited through `WizardPanel.item_changes/3` and `Structures.edit_item/3` (**37 bytes differ**, all inside the records of items 1 and 2), written to slot 8 (the old slot 8 is
in `~/.mirror/dev/DOSbox/backups/SAVE8-pre-itemedit-2026-10-15.GAM`). Research DOSBox, Load Game, then Armies > Items and a right-click on an item for its info:

| Item | Edit | The game shows |
| --- | --- | --- |
| Mae Govannon, Sir Harold's sword | name "Test Blade", cost 1300, attack 1 to 2, movement 0 to +1 (byte 2), powers Lightning + Haste | **Test Blade**: +2 Attack, +1 Defense, +1 Movement, +5 Spell Skill, Lightning (armor piercing); **Haste, doubles attacks** appears once a line is free |
| Protection of Ramses, the vault's shield | name "Odd Shield", **Flaming added** (a weapon power on a shield) | **Odd Shield**: +6 Defense, +4 Movement, Cloak of Fear, Endurance, **Flaming, +3 attack strength** |

- The game's memory held exactly the edited item block after loading (`0x87F70`), and **again after one End Turn** (byte-identical both times). The Items screen after the turn read the same.
- **The item info box shows at most five lines.** The sword's Haste was in memory and in the save but not listed; clearing its movement byte in the running game (memory only, one compare-and-swap write, put back afterwards) made the box list it.
  So an item with more than five lines shows only the first five: the page lists everything.
- **Answers the open question:** the game accepts an item whose power does not fit its type (a Flaming shield) without complaint, shows it, and keeps it through a turn. What a Flaming *shield* does in a fight was not tried.
- Evidence in the Evi vault, collection `mom-live-2026-10-15`: checkpoints 113 (the odd shield loaded), 114 (the sword), 115 (Haste shown when a line is free), 116 (after End Turn, memory) and 117 (the shield after the turn), each with a screenshot.

Not checked: a charged spell or charges (not editable here), stat values above the premade maxima (refused by the editor), a fight with an edited item, and the story's other edits (move, create, remove).
