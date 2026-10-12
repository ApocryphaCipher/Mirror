# STORY-049: Spell library and research

**Parent:** [EPIC-009](../epics/EPIC-009-wizard-editing.md)
**Status:** built and checked in the real game (2026-10-12), PR open
**Size:** medium
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-12 ("what the wizard is researching")

## What to do

- The spell numbering is in the game folder's `MMOMS.TXT` (appendix A.2): 0 to 239 by realm in the order Nature, Sorcery, Chaos, Life, Death, Arcane (40 per realm; Arcane uses 200 to 213), which gives the names without a new file; the old editor's states are *not known / known / unchangeable (in the research book) / researchable*, our 0, 2, 3 and 1.
- Show and edit the **spell library** (`+0x264`, 214 states: 0 unknown, 1 knowable, 2 known, 3 on the research list,
  [wizard-record-and-exploration.md](../reference/wizard-record-and-exploration.md)), grouped by realm with the spell
  names (the game's own `SPELLS.LBX` has them; it is not in the manifest yet, so adding it means a `Mirror.GameFiles.manifest/0`
  change and Kevin's say-so, per AGENTS.md section 5).
- **Researching** (`+0x262`) and **research points left** (`+0x25a`): choose another spell, set the points left, or finish it now.
  The eight research candidates (`+0x34`) are what the game offers next.
- A bulk "learn every spell of a realm" button, since that is the common edit (Kevin's Jafar has every Sorcery spell).

**Checked already:** setting Nature spells to 2 made 17 appear in the spellbook; the other 5 are combat-only and not listed
overland. **To check:** whether a known spell needs the wizard's books for the realm (a wizard with no Chaos books who
knows Chaos spells), the research candidate rules, and what the game does with a researching spell that is already known.

## Definition of done

Each edit loaded in the real game and read back; the Research and spellbook screens agree; tests as in STORY-048.

## Outcome (2026-10-12)

Built: `Mirror.Spells` (the spell table from `SPELLDAT.LBX`, added to `Mirror.GameFiles.manifest/0` as optional; names, realm, casting and
research cost by spell number), `Structures.edit_wizard/3` with `:spells`, `:researching` and `:research_left`, and on `/wizard/:id` the spells
grouped by realm (names; a tick box per spell and a "Learn every ... spell" button per realm in edit mode), the research picker and the points
left. Without the file the page shows `Spell N` and says how to import it.

**Spell table, checked:** entry 0 of `SPELLDAT.LBX` is 215 records of 36 bytes; the record index is the spell number; `+0` name (18), `+23` realm
(0 Nature to 5 Arcane; agrees with the numbering for all 214), `+26` casting cost, `+28` research cost (Earth Lore 30 and 250, Raise Volcano 200 and 680).

**Real game (slots 7, checkpoints 107 for round 2):**

- *Round 1* (SAVE2-based): every Death spell given to Jafar, who has **no Death books**: they appear in the spellbook and can be cast. Researching was set
  to Raise Volcano (spell 98, state 0 = unknown, **not one of the eight candidates at `+0x34`**) with 1 point left: the Magic screen said "Researching:
  Raise Volcano", the **Research page could not show it** (stuck), and at End Turn the spell was learned with no message. So the page now only offers
  the game's candidates (and the spell being researched); anything else is refused (`:not_offered`).
- *Round 2* (the advanced SAVE2): spell 42 (Dispel Magic True) set from known (2) to knowable (1); researching Recall Hero (205, a candidate) with 1 point
  left. The Research page drew it normally; at End Turn Recall Hero was learned (state 2). Read back from RAM: the candidate slot that held 205 now holds
  **42**, spell 42 is state **3** (on the research list), and the game was set to research it with **40 points left**, which is its research cost in
  `SPELLDAT.LBX`. So: knowable (1) spells are offered as new candidates, a chosen one becomes 3, and the points left start at the spell's research cost.
- In the advanced SAVE2 Jafar is researching spell 53, which is already known (state 2), and the game counts its points down (400 to 241 over turns):
  a researched spell does not have to be unknown.

**Not done / open:** whether a spell with state 0 (unknown) can be offered by setting it to 1 or 3 (no test yet); what the game does if the candidate list
and the library disagree beyond the cases above; editing the eight candidates themselves.
