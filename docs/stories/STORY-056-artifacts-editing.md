# STORY-056: Edit, move and create artifacts

**Parent:** [EPIC-011](../epics/EPIC-011-artifacts.md)
**Status:** third slice built (2026-10-15): a hero's or the vault's place can be filled with a premade item or emptied, checked in the real game. Second slice built and checked in the real game (2026-10-15): items can be moved between a hero's places and the vault. First slice built and checked in the real game (2026-10-15): an item can be edited in place (name, cost, stats, special powers) from the wizard page, loaded and kept through one End Turn; move, create, remove and a lair's reward are not built. *Original note:* open (2026-10-12), after STORY-055
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

## Second slice built (2026-10-15): move an item

In edit mode an item that has somewhere to go gets a **Move to** list on `/wizard/:id`: the vault (its first empty place) and every empty place of a hero whose **slot type** is the item's kind.
`Structures.move_item/4` writes the item index into the target and `-1` into the source (four bytes change, the item record is untouched), as one undo step. A swap is two moves through a free place.

- **A hero's place has a slot type** (`+22` of his list entry: 1 melee weapon, 2 bow, 4 staff or wand, 5 armor, 6 misc) and the item's slot code (`+32` of its record) must equal it. Sir Harold's places are (1, 5, 6): a sword, an armor and a misc item.
  **The game does not enforce it** (checked 2026-10-15, below): an armor placed in a misc place was drawn there, with no complaint, and kept through an End Turn. The editor still refuses a mismatch (`:wrong_slot`) because nothing is known about what such an item does in play; relaxing it is a one-line change.
- Moves stay inside one wizard (his heroes and his vault). Giving an item to another wizard's hero or vault is not built.
- Refused with a reason: nothing at the source, a taken target, a hero not in the list, a wrong kind of place, the same place twice, a free item record.
- `Heroes` now also reports each hero's `item_places` (the three places with their gaps) and `slot_types`; `Items.vault_places/2` the four vault places with their gaps.

### Real-game check of the move (2026-10-15)

Test save: `SAVE2.GAM` with two moves made by `Structures.move_item/4` (**5 bytes differ**): the Plate of Enduring Immunity from Sir Harold's armor place to the vault's second place, then Protection of Ramses from
the vault's first place to his armor place. Written to slot 8 (the previous slot 8 is in `~/.mirror/dev/DOSbox/backups/SAVE8-pre-itemmove-2026-10-15.GAM`). Research DOSBox, Load Game, Armies > Items:

- Loaded without complaint. The game's memory had hero places (1, 2, -1) and vault (-1, 0, -1, -1), exactly the save, and the item block unchanged. The Items screen shows Sir Harold with his sword and the shield, and the red plate in the vault's second place. **One End Turn later** the places and the item block were unchanged. (vault checkpoints 118 and 119)
- **Wrong-kind placement, by writing the game's memory (nothing saved):** the plate (armor, slot code 5) put into Sir Harold's third place (slot type 6, misc). The Items screen draws it there, no crash; after another End Turn the placement was still (1, 2, 0). (checkpoints 120 and 121)
  So the game does not check an item's slot code against the place's slot type on display or over a turn. *Not tried:* whether the bonus counts, picking the item up with the mouse, or putting it back in play.

Not built: giving an item to another wizard's hero or vault, create, remove, and a lair's reward.

## Third slice built (2026-10-15): fill a place with a premade item, or empty it

Kevin's design (2026-10-15): the game does not build artifacts from powers, it draws them from the premade table, so Mirror offers that table. In edit mode **every item place gets a drop-down**: a hero's three places (each
lists the premade items whose slot code equals that place's slot type) and the vault's four (any premade item). "(keep what is there)", "(remove the item)" and "(empty)" are in the list too.

- **The table is `ITEMDATA.LBX`**, 250 records of 56 bytes, read by `Mirror.ItemData` (now in the manifest, no hash; Kevin agreed to adding it). Two copies exist: `~/DOS/MAGIC` (rewritten by ITEMMAKE on 2026-10-12) and `~/DOS/MagicCom`
  (2024); they differ only in the cost and the 6-byte tail of about 100 records, all stat bytes agree. The copy in `~/.mirror/game` is MagicCom's.
- **A premade record stores movement as the screen shows it; a save stores half points**, so `ItemData.save_record/1` doubles it (Protection of Ramses: 4 here, 8 in a save).
- `Structures.put_item/4` writes the 50-byte record: **over the record the place already holds** when nothing else points at it, else into **the first free record** (an empty name that no place points at) and the index into the place.
  `Structures.clear_item/3` empties the place and **blanks the record** (50 zero bytes) when nothing else points at it. 138 records is the limit (`:no_free_item`).
- **In a real save an empty hero slot is unit -1 but its three item places read 0**, not -1 (SAVE2). Counting those as references would make item 0 look shared, so only existing heroes' places count.
- The game's own **free-record marker is unknown**: Mirror reads an empty name. A premade-items-still-available table the game keeps (kazzmir `loadPremadeItems`, 250 bytes, location not found) is **not** updated, so the game may later draw the same premade item again.

### Real-game check of the premade items (2026-10-15)

Test save: `SAVE2.GAM` through `clear_item/3` and `put_item/4` (**119 bytes differ**, all in the item block, Sir Harold's list entry and the vault; the previous slot 8 is in
`~/.mirror/dev/DOSbox/backups/SAVE8-pre-premade-2026-10-15.GAM`): the Plate removed from his armor place, then a Ring of Power in his misc place, a Chainmail of Speed in his armor place,
an Elvish Longbow in the vault's second place, and Protection of Ramses' record overwritten with a Shield of Speed. Research DOSBox, Load Game, Armies > Items, right-click for each item's info:

| Place | Premade item put in | The game shows |
| --- | --- | --- |
| armor (record 4, a free record) | Chainmail of Speed (table: defense 4, movement 4, resistance 4) | **+4 Defense, +4 Movement, +4 Resistance, Endurance** |
| misc (record 0, the removed Plate's blanked record, reused) | Ring of Power (table: 2, 1, 2, spell skill 5) | **+2 Defense, +1 Movement, +2 Resistance, +5 Spell Skill** |
| vault 0 (Ramses' record 2, overwritten in place) | Shield of Speed (table: defense 2, movement 3) | **+2 Defense, +3 Movement** |
| vault 1 (record 5, a free record) | Elvish Longbow | drawn as a bow in the vault |

- Loaded without complaint; the game's memory held the places (1, 4, 0) and (2, 5, -1, -1) and the item block exactly as in the file, **and again after one End Turn**. (checkpoints 122 to 126)
- **The doubling of movement is confirmed** (a premade 4 is the byte 8 in the save and reads +4; 3 is 6 and reads +3). A blanked record is reused without trouble, and a record is overwritten in place without trouble.
- **Remove**, simulated in the running game's memory (nothing saved): the bow's place set to -1 and its record zeroed, as `clear_item/3` does. The Items screen no longer showed the bow, and after another End Turn the places and the blank record were unchanged. (checkpoint 127)
  Not tried: a **save written by `clear_item/3`** and loaded as such (the memory state is the same bytes), and the game's own free-record marker (an all-zero record works, which is all Mirror needs).
- Not checked: whether the game later draws a premade item Mirror already placed (the "still available" table is not updated), and what a Chainmail of Speed does in a fight.
