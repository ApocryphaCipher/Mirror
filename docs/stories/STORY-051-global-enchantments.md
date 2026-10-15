# STORY-051: Global enchantments: see, add, remove

**Parent:** [EPIC-009](../epics/EPIC-009-wizard-editing.md)
**Status:** built (2026-10-15): the wizard page edits the 24 flags (Time Stop excepted); not retried in the game here, see "Built (2026-10-15)" below. *Original note:* open (2026-10-12). **Decoded in the real game:** an active global is a **1** in its byte (checked for Aura of Majesty, byte 3, and Just Cause, byte 18). Showing, adding and removing are not started.
**Size:** medium to large (the decode decides)
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-12

## What to do

0. **Found (2026-10-12), see [wizard-heroes-diplomacy-items.md](../reference/wizard-heroes-diplomacy-items.md):** 24 bytes at `+0x482` of the wizard record of the caster, in the order of the manual's globals list (Eternal Night first). The old DOS editor's wizard screen has a "globals" yes/no, so they are flags, which fits. SAVE2 has none active, so the value of an active one is not seen: have Kevin cast one (Nature Awareness is cheap) and read it back.
1. **Confirm** (was: decode) where the save keeps the global (overland, whole-world) enchantments and who cast each: the spells that
   stay active until dispelled, such as Eternal Night, Evil Omens, Zombie Mastery and the like. *Unknown:* whether they are
   in the wizard record (per caster) or in a block of their own, and the encoding (a list of ids, or flags). kazzmir's loader
   first; then a real game where Kevin casts one and the memory is diffed before and after.
2. **Show** them on the wizard page of the caster, and as a list on a world page (*proposed:* a small panel on the map).
3. **Add and remove.** Removing is the safe one; adding needs the spell's effect to be something the game derives from the
   flag and does not need a second write elsewhere (like a city enchantment, whose effect the game computes). Check each
   enchantment's effect in the game; list those that need more than the flag as not editable, as the lair panel does for items.

## Definition of done

A documented layout with two sources, and one enchantment added and one removed, loaded in the real game and visible in
its own screen (the Magic screen's active-spells list), surviving one End Turn.

## Decode results (2026-10-12)

Casting two globals in the real game (vault checkpoint 108) set exactly one byte each of the caster's 24, to 1: **byte 3 for Aura of Majesty** (the manual's list names
index 3 "Aura of Mastery"; it is the same spell) and **byte 18 for Just Cause**. So the list order of `MMOMS.TXT` appendix A.3 is the byte order, and the encoding is 0/1.
Spells are cast at End Turn, so the flag appeared then. The effects follow from the flag (Aura of Majesty raised relations each turn, with no other byte written for the spell
itself; the relations are the diplomacy block's job). *Not yet seen:* the other 22 bytes, what the game does with a flag set by hand (does the effect start; is the upkeep
charged; does the spell show in the Magic screen's list), and removing one (does it stop at once).

**Built (2026-10-13):** the wizard page lists the caster's active globals by name (read-only; only byte 3 and 18 have been seen set, the other names are the book's order). **Suggested next step:** one edit test on a copy of the advanced SAVE2: set Nature Awareness (byte 7, cheap) by hand, load it, look at the Magic screen's list and the map,
End Turn once and see the upkeep; then clear it and check that it goes away.

## Built (2026-10-15)

Editing: `/wizard/:id` in edit mode has a checkbox per global; `Structures.edit_wizard/3` takes `globals: [24 booleans]` and writes 0 or 1 at
`+0x482 + n`, one undo step like the other wizard edits. **Time Stop (byte 6) is not editable:** the form disables its box and `edit_wizard/3` refuses a
list that changes it (`:bad_globals`).

Evidence taken from the mompy project instead of a new game session (`~/repo/mompy/docs/reference/globals.md`, Kevin's game, 2026-10-13/14): a
hand-set flag shows in the Magic screen's "Overland Enchantments" box at once and survives End Turn; the game charges its upkeep (four cheap
globals together cost 17 mana a turn; Planar Seal 2). Effects seen for Aura of Majesty (relations rise), Great Wasting (corrupted tiles) and
Meteor Storm (a volcano). **Time Stop** set by hand only draws the icon and charges about 100 mana, with no effect; the real spell keeps its state
elsewhere (not found), so it is left alone. Not tried anywhere: an unaffordable upkeep, a value other than 1, two wizards holding the same global.
Mirror's byte index is mompy's number minus one (Aura of Majesty is byte 3, mompy's #4).

Not done: a list of globals on a map or world page (step 2's "proposed" panel).
