# STORY-053: Edit a hero

**Parent:** [EPIC-010](../epics/EPIC-010-heroes.md)
**Status:** partly built (2026-10-15): name, level, experience and damage are editable from the wizard page, and a hero can be added to an empty hero place from a drop-down (not yet loaded in the real game); giving a hero to another wizard, dismissing and adding are not built, and nothing was loaded in the real game. *Original note:* open (2026-10-12), after STORY-052
**Size:** medium
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-12

## What to do

- Edit a hero's **name**, **experience** (and with it the level, which the game recomputes at End Turn) and **damage**.
- **Give a hero to another wizard:** write the unit's owner and move the entry between the two hero lists, with the rules
  the unit editor already has (one owner to a tile, not into another owner's city) plus a free slot in the new list.
  This lifts `Structures.edit_units/3`'s `:hero_owner` refusal for the case the list handles.
- **Dismiss** a hero, and **add** one (a hero unit type 0 to 34 into a free slot): *open question* whether to build this at all;
  hiring has game rules (fame, gold) that the save does not enforce.

## Definition of done

Each edit loaded in the real game, read back from memory, shown correctly on the Heroes screen and surviving one End Turn;
tests as in STORY-048.

## Built (2026-10-15)

In edit mode each hero on `/wizard/:id` has a small form: **name** (1 to 13 printable ASCII characters, the list entry's 14 bytes are NUL-padded), **level**,
**experience** and **damage** (the unit's `+12`, `+14`, `+17`, with the limits `Structures.edit_units/3` already has). `Structures.edit_hero/4` does the write; one
apply is one undo step, like the other wizard edits. The game works the level out from experience again at End Turn, so experience is the lasting field.

Not done, and why:

- **Give a hero to another wizard:** needs the entry moved between two hero lists, the unit's hero slot (`+6`) rewritten, the items carried over and the
  unit editor's tile rules; none of that has been seen in the real game, so `edit_hero/4` and the unit editor still refuse an owner change (`:hero_owner`).
- **Dismiss and add:** the open question stands (hiring has rules the save does not enforce).
- **The real-game check** (Heroes screen, one End Turn) from the definition of done: not run. *Guess:* a renamed hero shows his new name on the Heroes screen, as
  the list entry holds the name; unchecked.

## Adding a hero (2026-10-15), Kevin's design

"We can just put drop downs under the heroes section for empty hero slots and pick a game hero from the list." In edit mode the Heroes section has **Add a hero**: all 35 heroes by name, minus any that has a live unit (whoever owns him),
for the first empty hero place. **No overwriting a hero** (levels, gear). `Structures.add_hero/4` writes, as the three heroes in SAVE2 show a hire does (*not yet loaded in the real game*):

- a **unit record** appended at the end of the unit table and the live count at `0x9E2` raised: owner, the wizard's **summoning circle** as the tile, 4 half-points of movement, the list slot at `+6`, level 0, no experience, sight 1, and the filler bytes the game's own
  hero units have (`+18` draw priority 8, `+28` 255). Field names are kazzmir's `UnitData`.
- the **hero list entry**: the unit index, the type's name, three empty places (-1) and the three **slot types** of the hero (below);
- the per-player hero table's first word for that hero set to **-20**. kazzmir calls that word `Level`; in SAVE2 it is -20 for every hired hero (Sir Harold and Warrax for the player, Bahgtru for the first rival) and 0 for the 32 others;
- for the **player** (record 0) the **hero-name table** at the end of the save (35 x 14-byte name + experience): SAVE2 has Sir Harold and Warrax in it, not the rival's Bahgtru. (It also has a "Z" at type 18 that nobody can account for: a test by hand.)

**Slot types** (`Mirror.SaveFile.HeroTypes`): 1 melee weapon, 2 bow, 3 any weapon, 4 staff or wand, 5 armor, 6 jewelry. Fighters (1, 5, 6), mages (4, 6, 6), archers B'Shan, Shuri, Marcus, Alorra (2, 5, 6) and Reywind, Mystic X and Warrax (3, 5, 6): from kazzmir's `GetArtifactSlots`,
matched by name, and **checked against all 15 hero types that appear in the local saves** (including mages, an archer and Warrax). A place of type 3 takes a melee weapon, a bow or a staff (`Items.slot_accepts?/2`); before, the item drop-downs offered nothing for it.

Refused with a reason: no empty place, a hero already in play, a summoning circle off the map, nine units already on that tile, a full unit table.

*Not known:* what the unit counters at `0x9D8` (the 7th and 8th words change between saves: 28 and 128, 30 and 82 ...) mean; they are not touched. And the draw priority and the movement are a default (8, and 4 half-points) not worked out per hero type: the game recomputes the movement
with items, and the draw priority only orders a stack. A load in the game will tell if the hero looks right.
