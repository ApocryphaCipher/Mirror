# STORY-049: Spell library and research

**Parent:** [EPIC-009](../epics/EPIC-009-wizard-editing.md)
**Status:** open (2026-10-12), after STORY-048
**Size:** medium
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-12 ("what the wizard is researching")

## What to do

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
