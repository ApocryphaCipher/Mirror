# STORY-050: Relations between wizards: peace, war, attitude

**Parent:** [EPIC-009](../epics/EPIC-009-wizard-editing.md)
**Status:** built (2026-10-13): shown and editable on the wizard page, checked in the real game (checkpoint 109). *Original note:* **Decode largely done** (see the findings in the reference doc): visible relations, pact status, interest values and threat flags confirmed in the real game; war (3) and alliance (2) not yet changed. Showing and editing are not started.
**Size:** large (the decode decides)
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-12 ("a relationship editor", "peace/war tags")

## What to do

0. **Found (2026-10-12), see [wizard-heroes-diplomacy-items.md](../reference/wizard-heroes-diplomacy-items.md):** the block is 306 bytes at `+0x128` of each wizard's record, with arrays by other player: contacted, treaty/peace/trade interest, **visible relations** (what the Diplomacy screen shows), **diplomacy status**, default and hidden relations, broken treaty, tribute, warning progress. SAVE2's values are sensible. The old DOS editor in the game folder has no diplomacy screen, so there is no 1995 precedent.
1. **Confirm.** The status code's meaning is a *guess* (ReMoM's names: 0 none, 1 wizard pact, 2 alliance, 3 war, 4 final war). Have Kevin make a treaty and break one in the real game and diff the memory. Original task, now narrowed: where the save keeps, for each pair of wizards, the diplomatic state (peace, war, an alliance or treaty
   if the game has one), the attitude or relation number the AI uses, and any treaty timers. *Unknown:* all of it. Start
   with kazzmir's loader (`load.go`), then confirm by diffing two saves of the same game that differ only in a diplomacy
   event (Kevin makes peace with a rival, or breaks a treaty, and saves), and read the changing bytes from the game's memory
   with the DOSBox fork ([live-ram-map.md](../reference/live-ram-map.md)). Write it up in `docs/reference/`.
2. **Show it** on each wizard's page: for every other wizard, the state as a tag (Peace, War, ...) and the attitude, with a
   link to that wizard.
3. **Edit it**: set the state and attitude for a pair. Check whether the game keeps the pair's two directions in step (A's
   view of B and B's view of A) or whether both have to be written; the editor writes both if both exist.

## Definition of done

A documented layout with two sources; one edited relation loaded in the real game and visible on its Diplomacy screen, and
the AI behaving as the new state says over one End Turn (it does not break a peace on the spot, or if it does, that is noted).

## Decode results (2026-10-12)

Checked by a real-game session (vault checkpoint 108; [findings](../reference/wizard-heroes-diplomacy-items.md#findings-2026-10-12-aura-of-majesty-just-cause-gold-a-pact-and-threats)):

- `+42` **visible relations** are what the Diplomacy screen shows, kept on **both** wizards' records (a gift or a threat changes both). Aura of Majesty
  sets them to 20 and adds 2 a turn; 50 gold buys +3 or +4, 100 gold +6; a threat costs 5 to 8.
- `+48` **status**: a pact is **1** on both records (0 none). 2 (alliance) and 3 (war) fit the saved values, *not yet changed*.
- The interest values (`+6`, `+18`, `+30`) drop when a treaty is made or a threat is made; they are the wizard's own willingness, held in the wizard's own block.
- A refusal changes nothing. Peace is only offered at war, war only when relations are bad.

**What editing needs to know before it is built:** write both records' relation and status (the game keeps both); whether a status set by hand is kept
or undone at the next turn (test: set a pact, End Turn); whether the interest values need to follow (they are the AI's willingness, so a pact
with interest left high may be broken at once). The tags to show: None, Pact, Alliance (*guess*), War (*guess*).

**Built (2026-10-13):** (a) the relations table (name linked to the wizard's page, standing, relation, met) on each wizard's page, read-only; a standing whose meaning is unchecked (alliance, war) carries a "?". *To do for this part:* compare the table with the game's own Diplomacy screen for Jafar. **Suggested next steps:** (b) one edit test: set a pact and
a relation on a copy of the advanced SAVE2, load it, read the Diplomacy screen, End Turn once; (c) set a status 3 (war) and 2 (alliance) the same way, which
also settles their meaning.

## Outcome (2026-10-13)

Built: `Structures.edit_wizard/3` takes `:relations` (a list of `{other wizard 0..4, relation -100..100 or nil, status 0..4 or nil}`) and writes the pair on **both** wizards' records;
the wizard page's Relations table has, in edit mode, a number box (-100 to 100) and a standing select (None, Wizard pact, Alliance, War) on each row except the neutral
player's, one Apply, one undo step, a label "relations with ..." and a refusal that says why. Only fields that differ from the save are written.

**Real game (slot 7, checkpoint 109):** all four statuses are now confirmed by the game's icons and menus (details in the [reference doc](../reference/wizard-heroes-diplomacy-items.md)):
0 none (which is also what peace is), 1 wizard pact, 2 alliance, 3 war. The hand-written values loaded as written, the Diplomacy menu followed the status, a peace treaty with the wizard at
war (even at -90) was accepted and set 3 back to 0 with +40, and one End Turn kept the alliance and the relations. *Untried:* status 4; the neutral player's row; whether the AI later
breaks a hand-made alliance when its other relations disagree (it did not in one turn); writing the interest values (left alone).
