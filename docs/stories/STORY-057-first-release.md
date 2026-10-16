# STORY-057: The first release

**Parent:** none (cross-cutting)
**Status:** plan written (2026-10-15); not started
**Size:** medium
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-15

## Decision: source only

Mirror is released as **source**: a tagged commit on `main` plus release notes on GitHub. There is **no published Docker image and no registry** (Kevin, 2026-10-15: too much to run).
People get it with `git clone`, then either `mix setup` + `bash scripts/dev_server.sh` (Elixir toolchain) or `docker compose up --build` (builds the image on their machine; compose's placeholder `SECRET_KEY_BASE`
is fine for localhost only). CI keeps building the image and smoke-testing it, so the Docker route stays working. The game files are never shipped: each user imports their own copy with `mix mirror.import_game`.

## What 1.0 covers

In: the map pages (view and edit: terrain, roads, specials, corruption, reveal, moving cities, towers, lairs, nodes and stacks, and the city, lair, node and unit panels), Save as with the safety rules, undo/redo,
the wizard pages (wizard, relations, globals, heroes, artifacts), the Lab and the tile probe as research tools. Every editor above was checked in the real game (GOG 1.31 under DOSBox).

Out, stated plainly in the README and the notes: the raw tile tools do not keep landmass ids consistent (STORY-017, STORY-029); saves are only checked from the GOG 1.31 game (Steam is untested, see the backlog);
hero ability names, hero rename vs the name table, and what a Time Stop edit does are not handled or not known; no multiplayer-specific or other-version saves.

## Checklist

1. README is true: install, import, run (source and Docker), where saves go. **Done 2026-10-15** (this story's PR): file count and which files are optional, the start step, how to load a save, the stale offsets claim removed, "no published image".
2. A clean-install run from the README on a fresh machine or folder: `git clone`, `mix setup`, import, run, load a save, edit, Save as, load it in DOSBox. Not done.
3. The Docker route from a clean checkout, game files mounted, loads a save. Not done.
4. Test on a Steam copy if there is one (backlog item).
5. Licence: **GPL-2.0** (Kevin, 2026-10-15; the engine files are GPLv2 ports of MOMIME, so the whole project is GPL-2.0). `LICENSE`, README and `NOTICE.md` are in their own PR. Done once that merges.
6. Version: `mix.exs` says 0.1.0. Pick the first tag (suggest `v0.1.0`, since safe editing STORY-029 is open), bump if needed.
7. CI green on `main` (format, warnings-as-errors compile, tests, Docker smoke test), `mix test --seed 1 --max-cases 8` clean.
8. Repo hygiene: nothing from a game file in the tree or the history (AGENTS.md section 5); `erl_crash.dump` and `tmp/` are not tracked.
9. Tag, GitHub release notes (what it does, the limits above, how to install), link from the README.

## Not decided

Decided: do **not** wait for STORY-029 (Kevin, 2026-10-15); the limit is stated in the notes instead.
