# STORY-030: Docker image and compose file

**Parent:** [EPIC-007](../epics/EPIC-007-packaging-ci-and-repo-hygiene.md)
**Status:** open, in review (PR #69) — image builds but doesn't boot on the
author's Mac; see Outcome below for why and what's next
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

## Outcome (in progress — not Done, see below)

Added `Dockerfile` (multi-stage: `hexpm/elixir` builder, `debian:bookworm-slim`
runtime, non-root user, `MIX_ENV=prod` throughout), `compose.yaml` (bind-mounts
`${MIRROR_HOME:-~/.mirror}/game:/game` and `${MIRROR_HOME:-~/.mirror}:/data`,
dev-only `SECRET_KEY_BASE`), a `docker-build` CI job that builds the image
*and* boots it + curls `/arcanus` (build succeeding isn't enough — see why
below), and a README Quick start entry. Dropped the now-redundant
`MIRROR_*_OFFSET` exports from `scripts/dev_server.sh` (`config/config.exs`
already has correct defaults; confirmed `scripts/test_game.sh` still picks up
`MIRROR_MOM_PATH`).

Drafted by Qwen3.8 via Aider (NUC). Reviewing it by actually running things,
not reading the diff, turned up three real bugs, two fixed:

1. **Fixed.** Base image tag `hexpm/elixir:1.20.4-otp-29.1` doesn't exist —
   the real tag format includes the full OTP patch and base OS
   (`1.20.4-erlang-29.1.1-debian-bookworm-20260918-slim`), confirmed against
   Docker Hub's actual tag list, not guessed.
2. **Fixed.** `mix release`'s real output is `_build/prod/rel/mirror/`, not
   `_build/releases/mirror/` as first drafted — confirmed by running
   `mix release` directly. Also: the Dockerfile only copied `bin/` and
   `releases/` from it, missing the release's own `erts-*/` and `lib/`
   directories entirely (the bundled Erlang runtime and compiled app code) —
   changed to copy the whole release directory instead of cherry-picking.
3. **Fixed.** The slim builder image has no `git`, needed because `mix.exs`
   fetches the `heroicons` dependency straight from GitHub rather than Hex —
   `mix deps.get` failed until `git` was added to the builder stage.

**Unresolved — the image still doesn't boot on this Mac.** After all three
fixes above, `docker build` succeeds, but `docker run` fails:
```
/app/releases/0.1.0/../../erts-17.1/bin/erl: exec: /app/erts-17.1/bin/erlexec: Exec format error
```
Checked the actual bytes: the *base* `hexpm/elixir` image's own
`erts-17.1/bin/erlexec` is a correct Linux ELF binary (`7f 45 4c 46`). But
after `mix release` bundles/copies it into `_build/prod/rel/mirror/erts-17.1/`,
that same file comes out as a **macOS Mach-O binary** (`cf fa ed fe`) instead
— reproduced from a fully clean `docker build --no-cache`, and with BuildKit's
provenance/SBOM attestation explicitly disabled, so neither caching nor that
metadata step explains it. I could not root-cause this further without more
time; my best guess is something specific to Docker Desktop for Mac's
virtualization on Apple Silicon (this machine), not a Dockerfile bug — but I
haven't confirmed that, and CI (native Linux) may or may not hit the same
thing since its `docker-build` job never previously *ran* the image, only
built it (now it does, via the new boot-and-curl step above — that step will
tell us whether this reproduces there).

**Next step:** check whether CI's new boot-smoke step passes on GitHub's
Linux runner. If it does, this was Docker-Desktop-for-Mac-specific and the
story can go straight to Done. If it fails there too, this needs a real
investigation (possibly `mix release`'s `:erts_dir` resolution, or a
Docker Desktop VirtioFS interaction) before merging.
