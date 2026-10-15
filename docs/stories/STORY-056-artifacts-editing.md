# STORY-056: Edit, move and create artifacts

**Parent:** [EPIC-011](../epics/EPIC-011-artifacts.md)
**Status:** first slice built (2026-10-15): an item can be edited in place (name, cost, stats, special powers) from the wizard page, not yet loaded in the real game; move, create, remove and a lair's reward are not built. *Original note:* open (2026-10-12), after STORY-055
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
- *Open, still:* whether the game accepts or repairs an item whose powers do not fit its type (a Flaming shield, a Regeneration sword); the form allows it. Nothing here was loaded in the game yet:
  the definition of done (rename, change a power, move, create, each seen on the item screen and through one End Turn) is **not** met; this slice covers rename and change a power and still needs that check.

Not built: **move** (between a hero's three slots, the vault and another hero: the list entries and their slot types), **create** (a free item slot: the game's rule for a free slot is unknown, an empty name is
what Mirror reads), **remove**, and a lair's reward items (a lair holds no item before it is cleared: STORY-054).
