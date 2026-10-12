# STORY-051: Global enchantments: see, add, remove

**Parent:** [EPIC-009](../epics/EPIC-009-wizard-editing.md)
**Status:** open (2026-10-12). The layout is located (see below); the non-zero encoding is unseen.
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
