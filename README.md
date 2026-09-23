# Mirror

Mirror reads a classic *Master of Magic* (1994 DOS) save file and draws the
overland map — terrain, coastlines, both planes (Arcanus/Myrror) — using the
game's own logic for which tile art goes where. It's a Phoenix/LiveView app;
the map renders live in the browser from a save you load in.

**Status, honestly:** the app currently renders terrain through a
MOMIME-derived PNG asset pack plus a ported smoothing algorithm. That works,
but it's being replaced: on 2026-09-22 we found that save terrain values
are tile numbers straight into the game's own `TERRAIN.LBX`, and a small
script ([scripts/mom_map_render.py](scripts/mom_map_render.py)) renders a complete, correct map
from classic art with no smoothing at all. See
[docs/reference/classic-terrain-format.md](docs/reference/classic-terrain-format.md). Moving the app onto that path
is [STORY-005](docs/stories/STORY-005-render-from-terrain-lbx.md). Cities, towers, and other overland features
are not implemented yet ([EPIC-004](docs/epics/EPIC-004-overland-map-features.md)). [docs/epics/](docs/epics/) is the living
status. This paragraph is a summary, not the source of truth.

## Quick start

You need:

- Elixir/Erlang (see `mix.exs` for version constraints)
- Your own copy of the classic *Master of Magic* game files (LBX files) —
  Mirror doesn't ship these, you provide them. It needs a **complete**
  install (the GOG release works); some CD-era installs leave
  `TERRAIN.LBX` and friends on the disc.
- A save file (`.GAM`) from that install

```bash
mix setup   # deps.get + assets.setup + assets.build
```

Then either:

```bash
mix phx.server   # bare — you'll need to set MIRROR_MOM_PATH and the
                  # MIRROR_*_OFFSET env vars yourself, see config/runtime.exs
```

or use [scripts/dev_server.sh](scripts/dev_server.sh), which sets all of that for you — edit the
paths at the top of the script to point at your own install, then:

```bash
bash scripts/dev_server.sh
```

Visit `localhost:4000`:

- `/arcanus`, `/myrror` — the map viewer for each plane. Load a save via the
  path field in the UI.
- `/tile-probe` — the LBX explorer/tinker tool: browse raw LBX entries,
  inspect decoded palette indices, hex-dump entries, test palette sources
  against each other. Built for exactly the kind of format archaeology this
  project needs a lot of.

## Why this needs real reverse-engineering, and how that's tracked

Mirror depends on undocumented binary formats (the classic save file, the
LBX asset containers) and on correctly reimplementing game logic nobody
published. The approach that's worked, repeatedly: find a primary source
(the actual game's own data, or another independent implementation) instead
of guessing from patterns — see [docs/notes/](docs/notes/) and
[docs/reference/](docs/reference/) for what's been found and where it came from
(MOMIME's production ruleset, a classic-save editor's source, the
community save-format wiki).

**`docs/` is where the actual project state lives** — epics, stories,
backlog, research notes. This README is an entry point, not a substitute
for it. If you're picking this project back up (human or AI), start at
[docs/README.md](docs/README.md).

## Keeping this file current

This README should describe what Mirror *actually does right now*, not
what it's supposed to do eventually — that belongs in `docs/epics/`.
Update the Status line above when something in `docs/epics/` materially
changes (a feature actually works now, or a fix landed), not more often
than that.

## Attribution

Mirror's rendering logic is informed by the MOMIME project (GPLv2) — see
[NOTICE.md](NOTICE.md) and [docs/reference/momime-source/](docs/reference/momime-source/) for specifics
and citations.
