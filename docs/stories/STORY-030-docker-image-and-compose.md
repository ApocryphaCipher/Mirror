# STORY-030: Docker image and compose file

**Parent:** [EPIC-007](../epics/EPIC-007-packaging-ci-and-repo-hygiene.md)
**Status:** open, not started
**Size:** small–medium
**Requested by:** Kevin, 2026-09-23

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
- **Save-block offsets** (`MIRROR_TERRAIN_OFFSET` etc.) are set only in
  `scripts/dev_server.sh` today. The container needs them too, so move them
  into one place both can use (config defaults, or an env file compose
  loads). Don't copy them into a third place.
- **Stats DETS file**: `Mirror.Stats` writes `priv/mirror_stats.dets`
  inside the app dir. In a release that belongs on a volume (or a
  configurable path), not in the image.
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
