# Mirror

Mirror is a viewer and editor for classic *Master of Magic* (1994 DOS) save
files. It reads a `SAVEn.GAM`, draws the overland map of both planes
(Arcanus and Myrror) with the game's own tile art, and lets you edit the
terrain and save the result back to a new `.GAM`. It's a Phoenix/LiveView
app; everything renders live in the browser.

**Status:** terrain renders directly from the game's `TERRAIN.LBX` and
matches a reference decode pixel for pixel. Cities are drawn with
owner-coloured flags and size-appropriate frames from `MAPBACK.LBX`. The map
pages have a view mode (zoom, pan, hover readout with the full Surveyor card,
and layer toggles for cities, settleable tile grading, and fog of war) and an
edit mode (cycle or paint tiles, undo/redo, Save as). Note on editing: today's
terrain editor updates terrain tiles and the recomputed adjacency mask only;
it does **not** keep landmass/continent IDs consistent across land/water
transitions (tracked in STORY-017 and STORY-029). Other overland features
(units with banner plaques, towers, encounter sites, roads, specials) and node
auras are next. The sprites for all of them are identified and decode correctly
([sprite catalog](docs/reference/overland-sprites-and-save-blocks.md)), but
they aren't drawn on the map yet ([EPIC-004](docs/epics/EPIC-004-overland-map-features.md)).
[docs/epics/](docs/epics/) is the living status; this paragraph is a summary.

## Quick start

You need:

- Elixir 1.20.4 / Erlang/OTP 29.1 (what CI uses; `mix.exs` has the minimum).
- Your own copy of the classic game files. Mirror doesn't ship them; they
  are copyrighted and must never be committed. You need a **complete**
  install (the GOG release works). CD-era installs often leave
  `TERRAIN.LBX` and others on the disc.
- A save file (`SAVEn.GAM`) from that install.

```bash
mix setup
mix mirror.import_game "/path/to/your/Master of Magic"   # an install folder or a .zip
```

`mirror.import_game` copies only the files Mirror reads (five LBX files,
plus your `SAVEn.GAM` saves) into `~/.mirror/game`, checks each one, and
says whether it matches the GOG release. Re-running it is safe: it never
overwrites a save you've edited unless you pass `--force`.

Then start the server with [scripts/dev_server.sh](scripts/dev_server.sh). It points
`MIRROR_MOM_PATH` at `~/.mirror/game` (override by setting it yourself) and
sets the save-block offsets (`MIRROR_*_OFFSET`).

```bash
bash scripts/dev_server.sh
```

Visit `localhost:4000`:

- `/arcanus`, `/myrror`: the map for each plane. Pan, zoom, inspect tiles with
  the Surveyor readout, and toggle layers (cities, settleable sites, fog of war).
  Load a save with the path field in the header (it defaults to
  `$MIRROR_MOM_PATH/SAVE1.GAM`), then ✎ Edit to cycle or paint terrain.
- `/lab/arcanus`, `/lab/myrror`: the research workbench. Raw layers,
  value/bit labelling, histograms, the raw-value painter.
- `/tile-probe`: the LBX explorer. Browse any LBX file's entries by name,
  preview images and animation frames in the game palette, and inspect
  palette indices and hex dumps.

## Tests

```bash
mix test                  # everything that doesn't need game files (including editing/save-safety tests)
bash scripts/test_game.sh # real-file tests using dev_server.sh's game-file env
```

Tests that need real game files read from `MIRROR_MOM_PATH` (or a frozen save
fixture for Surveyor tests, `MIRROR_SURVEYOR_SAVE`, which defaults to
`~/.mirror/dev/surveyor-fixtures/SAVE9-dior-2026-09-24.GAM`) and are skipped
when they are missing, so CI (which has no game files) runs `mix test` only.

`scripts/test_game.sh` exports the variables from `scripts/dev_server.sh`
(`MIRROR_MOM_PATH` and the save-block offsets), but does **not** set
`MIRROR_SURVEYOR_SAVE`. Running the Surveyor real-save tests therefore requires
manually exporting `MIRROR_SURVEYOR_SAVE` (or placing the frozen Dior save at the
default fixture path).

## Contributing

All changes go through a pull request: branch, commit, open a PR, CI
passes, merge. Nobody pushes to `main` directly. CI runs
`mix format --check-formatted`, `mix compile --warnings-as-errors` and
`mix test` on every PR and on `main`.

Coding standards and project conventions, for humans and AI agents, are in
[AGENTS.md](AGENTS.md).

## How the project is tracked

Mirror depends on undocumented binary formats (the save file, the LBX asset
containers) and on reimplementing game logic nobody published. What has
worked every time is finding a primary source instead of guessing from
patterns: the game's own data files, or an independent implementation.
[docs/reference/](docs/reference/) holds the format write-ups and where
each fact came from; [docs/notes/](docs/notes/) holds dated session notes.

**`docs/` is where the project state lives:** epics, stories, the backlog
and research notes. If you're picking this project up (human or AI), start
at [docs/README.md](docs/README.md).

## Keeping this file current

This README describes what Mirror does *now*; plans belong in `docs/epics/`.
Update the Status paragraph when something in `docs/epics/` materially
changes (a feature starts working, or a fix lands), not more often.

## Maintainer

Mirror is maintained by [Kevin Asbury](https://github.com/KevinAsbury). "Kevin"
in the docs and tickets means him.

## Attribution

Mirror's early rendering logic was informed by the MOMIME project (GPLv2).
See [NOTICE.md](NOTICE.md) and [docs/reference/momime-source/](docs/reference/momime-source/) for
details and citations.
