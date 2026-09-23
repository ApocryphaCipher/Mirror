# Mirror docs

**Picking this up? Read [notes/2026-09-23-session-handoff.md](notes/2026-09-23-session-handoff.md) first**, and
[../AGENTS.md](../AGENTS.md) for how we work (coding standards, git workflow, game-file rules).

Working docs for the Mirror project (Master of Magic save-file viewer). Not shipped with the app — this is planning/notes scaffolding.

- `epics/` — large bodies of work, one file each, status tracked at the top
- `stories/` — smaller units under an epic, linked back to it
- `backlog.md` — unsorted/uncommitted ideas and known issues, not yet promoted to a story
- `notes/` — dated session notes, investigation logs, things learned about the LBX/MOMIME formats that aren't obvious from the code
- `reference/` — format writeups and primary-source material. Start with `classic-terrain-format.md` (how the map is actually stored). Also MOMIME's real source (`momime-source/`), a classic-save editor's source (`momedit-source/`), and the original Codex planning docs (`codex-notes/`) that explain how earlier (wrong) approaches got built
