# STORY-061: Retire the path box and the old save-path rules

**Parent:** [EPIC-012](../epics/EPIC-012-open-and-save-from-the-browser.md)
**Status:** open (2026-10-15), after STORY-060
**Size:** small

## What to do

Once the slot flow has proved itself in daily use, remove the path box, `MIRROR_MOM_PATH`'s role as "where saves live" (it stays for the LBX files), the "next free slot" suggestion, `SaveFile.write/3`'s overwrite refusal and their tests, and update the README and AGENTS.md. Safari and Firefox users lose the path box too: the README says Chrome or Edge is needed to open and save (Kevin: others at their own risk).
Do this only on Kevin's say-so; until then the path box stays as a fallback.
