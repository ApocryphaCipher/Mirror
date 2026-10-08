# Mirror

Mirror is a viewer and editor for classic *Master of Magic* (1994 DOS) save
files. It reads a `SAVEn.GAM`, draws the overland map of both planes
(Arcanus and Myrror) with the game's own tile art, and lets you edit the
terrain and save the result back to a new `.GAM`. It's a Phoenix/LiveView
app; everything renders live in the browser.

**Status:** terrain renders directly from the game's `TERRAIN.LBX` and matches a
reference decode pixel for pixel, and the map pages draw the save's overland
features with the game's own art: cities (owner-coloured flags, population
frames, walls, names), units on banner-colour plaques, towers and encounter
sites, roads, specials and corruption, the sparkles on owned magic nodes, and the
player's fog of war. The ocean, the other animated tiles, the node sparkles and
enchanted roads move on the game's 0.6 s step (an **Animate terrain** toggle turns
it off). The map pages have a view mode (zoom, pan, a hover readout with the full
Surveyor card, and a toggle for each layer) and an edit mode: paint a terrain type
with auto-tiling, cycle or paint raw tiles, set roads, enchanted roads, corruption
and specials, reveal the whole map, undo/redo, and Save as. Note on editing:
**Paint type** keeps the landmass/continent IDs consistent; the raw tools (Cycle,
Paint tile) update terrain tiles and the recomputed adjacency mask only and do
**not** keep the landmass/continent IDs consistent (tracked in STORY-017 and
STORY-029). Next is moving and editing structures and units
([EPIC-006](docs/epics/EPIC-006-map-first-ui-and-edit-mode.md)). Every edit
feature is checked against the real game before its story is closed
([how](docs/reference/real-game-acceptance.md)). The sprites are catalogued in the
[sprite catalog](docs/reference/overland-sprites-and-save-blocks.md).
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

### Docker (no Elixir toolchain needed)

```bash
docker compose up --build
```

Builds the release image and starts Mirror on `localhost:4000`. Game files
and saves are read from (and written to) `~/.mirror/game` via a bind mount
(set `MIRROR_HOME` to use a different folder).

To import game files without an Elixir toolchain:

```bash
docker compose run --rm -v "/path/to/install:/source:ro" app bin/mirror eval 'Mirror.GameFiles.import("/source", "/game")'
```

(Or populate `~/.mirror/game` using `mix mirror.import_game /path/to/install` if you have Elixir installed.)

Visit `localhost:4000`:

- `/arcanus`, `/myrror`: the map for each plane. Pan, zoom, inspect tiles with
  the Surveyor readout, and toggle layers (cities, settleable sites, fog of war).
  Load a save with the path field in the header (it defaults to
  `$MIRROR_MOM_PATH/SAVE1.GAM`), then ✎ Edit. **Paint type** paints water or a land type (dropdown, brush 1×1 to 5×5, fill; right-click picks the terrain under the pointer) and re-tiles the coast and edges around it; **Paint tile** writes one exact tile number (with a quick pick of plain tiles) and leaves neighbours alone; **Cycle** steps a tile to the next picture. **Road** steps a tile none, road, enchanted road; **Corruption** switches it on or off; **Special** places an ore, gems, crystals, wild game or nightshade. **Reveal** marks every tile of this plane, or both, as explored. Undo and redo cover everything, including the landmass layer.
- `/lab/arcanus`, `/lab/myrror`: the research workbench. Raw layers,
  value/bit labelling, histograms, the raw-value painter.
- `/tile-probe`: the LBX explorer. Browse any LBX file's entries by name,
  preview images and animation frames in the game palette, and inspect
  palette indices and hex dumps.

## Tests

```bash
mix test                  # everything that doesn't need game files (including editing/save-safety tests,
                          # and the client's JavaScript unit tests in assets/test when `node` is installed)
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

**Checking against the real game.** Mirror's guesses about the formats are
checked in the real game, not assumed. For edits, load the saved file in DOSBox
([docs/reference/real-game-acceptance.md](docs/reference/real-game-acceptance.md)).
For research, a DOSBox Staging fork with a read-only web API lets an agent read
the running game's memory and screen
([docs/reference/live-ram-map.md](docs/reference/live-ram-map.md),
`scripts/live_session.sh`); it is a research tool, and Mirror itself never talks to
DOSBox.

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
