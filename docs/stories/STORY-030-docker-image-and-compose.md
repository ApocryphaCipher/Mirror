# STORY-030: Docker image and compose file

**Parent:** [EPIC-007](../epics/EPIC-007-packaging-ci-and-repo-hygiene.md)
**Status:** Done — verified end-to-end with real game files, including a Save-as round-trip
**Size:** small–medium
**Requested by:** [Kevin](https://github.com/KevinAsbury), 2026-09-23

## Goal

`docker compose up --build` runs Mirror against your own game files, with
no Elixir toolchain on the host. Follow shiba-mps's setup: a multi-stage
`Dockerfile` that builds an Elixir release (`hexpm/elixir` builder, slim
Debian runner, non-root user) and a `compose.yaml` at the root. Keep the
Elixir/OTP versions in step with CI.

## Mirror-specific constraints

- **Game files are never in the image.** They're copyrighted. The user
  runs `mix mirror.import_game` once (or the same task inside the container,
  see below), which fills `~/.mirror/game`. Compose bind-mounts that folder
  (`${MIRROR_HOME:-~/.mirror}/game:/game`) and sets `MIRROR_MOM_PATH=/game`.
  A bind mount beats a named volume here: the user can see and back up their
  saves. Offer an import path for people without Elixir, e.g.
  `docker compose run --rm -v "/path/to/install:/source:ro" app bin/mirror
  eval 'Mirror.GameFiles.import("/source", "/game")'`, wrapped in a
  release command. The image must build and start without
  them. The map then shows raw values, as it already does when
  `TERRAIN.LBX` is missing.
- **Saves are in the same mount.** The importer puts `SAVEn.GAM` in the
  game folder, the Load box defaults to `$MIRROR_MOM_PATH/SAVE1.GAM`, and
  Save as writes next to the loaded file, so `/game` must be writable.
- **Save-block offsets:** nothing to do. `config/config.exs` has
  defaults for all five (`Mirror.SaveFile.Blocks`), confirmed by the
  game's own save writes (docs/reference/save-to-ram-map.md). The
  `MIRROR_*_OFFSET` env vars only override them, so the container needs
  none. The exports in `scripts/dev_server.sh` are now redundant: drop
  them here, and check that `scripts/test_game.sh` still gets
  `MIRROR_MOM_PATH`.
- **Stats DETS file:** `Mirror.Stats` writes `Mirror.Paths.stats_file/0`,
  which defaults to `~/.mirror/stats.dets` and can be overridden with
  `MIRROR_STATS_FILE` (it's no longer in the repo; 2026-09-24). In the
  container, point it into the mounted folder, e.g.
  `MIRROR_STATS_FILE=/data/stats.dets` with `${MIRROR_HOME:-~/.mirror}`
  mounted at `/data` (and the game at `/data/game`), so the stats
  survive a rebuild.
- **Assets**: the release needs `mix assets.deploy` (esbuild + tailwind).
  Tailwind's standalone macOS binary had signing trouble locally (see the
  backlog). Linux in Docker should be fine, but check.
- `SECRET_KEY_BASE`: a dev-only placeholder in `compose.yaml` is fine
  (shiba-mps does the same, with a comment); a real deployment sets its own.

## Not in scope

- Publishing images or deploying anywhere.
- Containerising local development. `scripts/dev_server.sh` stays the
  normal way to work on Mirror; the container is for running it.

## Done when

- `docker compose up --build` serves Mirror on `localhost:4000`, renders a
  save's terrain from the mounted game files, and can Save as into the
  saves volume.
- CI builds the image (build only, no push) so the Dockerfile can't rot.
- README's Quick start mentions the Docker route.

## Outcome

Added `Dockerfile` (multi-stage: `hexpm/elixir` builder, `debian:bookworm-slim`
runtime, non-root user, `MIX_ENV=prod` throughout), `compose.yaml` (bind-mounts
`${MIRROR_HOME:-~/.mirror}/game:/game` and `${MIRROR_HOME:-~/.mirror}:/data`,
dev-only `SECRET_KEY_BASE`), a `.dockerignore`, a `docker-build` CI job that
builds the image *and* boots it + curls `/arcanus` (a successful `docker build`
turned out not to guarantee a working container — see below), and a README
Quick start entry. Dropped the now-redundant `MIRROR_*_OFFSET` exports from
`scripts/dev_server.sh` (`config/config.exs` already has correct defaults;
confirmed `scripts/test_game.sh` still picks up `MIRROR_MOM_PATH`).

Drafted by Qwen3.8 via Aider (NUC). Reviewing it by actually building,
booting and curling the image — not just reading the diff — turned up four
real bugs, all fixed:

1. Base image tag `hexpm/elixir:1.20.4-otp-29.1` doesn't exist — the real tag
   format includes the full OTP patch and base OS
   (`1.20.4-erlang-29.1.1-debian-bookworm-20260918-slim`), confirmed against
   Docker Hub's actual tag list, not guessed.
2. `mix release`'s real output is `_build/prod/rel/mirror/`, not
   `_build/releases/mirror/` as first drafted, and includes the release's own
   `erts-*/` and `lib/` dirs, which weren't being copied at all. Fixed by
   copying the whole release directory instead of cherry-picking `bin/` and
   `releases/`.
3. The slim builder image has no `git`, needed because `mix.exs` fetches the
   `heroicons` dependency straight from GitHub rather than Hex.
4. `mix assets.deploy` ran before `mix compile`, so Phoenix's colocated-hooks
   JS module (`phoenix-colocated/mirror`) didn't exist yet when esbuild tried
   to bundle it — this one only showed up in CI (native Linux), not locally,
   and is what an earlier draft of this note mistakenly attributed to a
   Docker-Desktop-for-Mac virtualization quirk (see below). Fixed by adding an
   explicit `mix compile` before `mix assets.deploy`.
   Also needed: `ENV PHX_SERVER=true` in the runtime stage — without it the
   release boots but the Endpoint never starts its HTTP listener
   (`config/runtime.exs` gates `server: true` on that env var, and nothing
   else in the release sets it).

**A wrong turn worth recording:** an earlier pass through this review found
the built image's bundled `erts-17.1/bin/erlexec` was a **macOS Mach-O binary**
instead of Linux ELF, and concluded (after ruling out BuildKit caching and
attestation) that this was likely a Docker-Desktop-for-Mac virtualization
quirk. That was wrong: there was no `.dockerignore`, and `mix release`/
`mix deps.get` had been run directly on the host (this Mac) inside the same
worktree during that verification — so `COPY . .` was silently pulling the
host's own macOS-built `_build/` and `deps/` directories into the image,
including a macOS-native `erlexec`. Adding `.dockerignore` (excluding
`_build/`, `deps/`, etc.) and rebuilding from a genuinely clean context
resolved it immediately — the container then hit the real bug (#4 above)
instead, on both this Mac and CI.

**Verified end-to-end, not just built:** ran `docker compose up --build`
for real (not just `docker build`, and not just an equivalent `docker run`)
against this Mac's own `~/.mirror` — the container starts, Bandit binds
`:4000`, and `curl localhost:4000/arcanus` returns `200` with a logged
`GET /arcanus` / `Sent 200`.

**Confirmed with real game files (Kevin, 2026-09-26):** loaded a real save
through the mounted `/game` folder and ran Save as inside the container —
it wrote to `/game/SAVE3.GAM`, i.e. next to the loaded file in the bind
mount, exactly as designed. Rendering and the save round-trip both work
against actual game data, closing the one gap left open above.
