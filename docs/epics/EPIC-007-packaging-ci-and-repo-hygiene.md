# EPIC-007: Packaging, CI and repo hygiene

**Status:** in progress
**Owner:** Kevin
**Requested:** 2026-09-23 (Kevin's "laundry list": Docker, README,
AGENTS.md, branch protection).

## Goal

Mirror should build, test and run the same way for everyone: on Kevin's
machine, in CI, and in a container. `main` only changes through reviewed
pull requests with green CI.

## Done

- **CI** ([.github/workflows/ci.yml](../../.github/workflows/ci.yml),
  2026-09-23): `mix format --check-formatted`, `mix compile
  --warnings-as-errors` and `mix test` on every PR and on `main`. Tests that
  need game files skip in CI. This needed the Elixir 1.20 warning cleanup
  from the backlog.
- **[AGENTS.md](../../AGENTS.md)**: the project's coding standards and
  conventions, adapted from the Shiba baseline.
- **README** rewritten for what Mirror does now.
- **Branch protection on `main`**: see the PR that added this epic for the
  exact rules. No direct pushes, PR required, CI required.

## Stories

- [STORY-030](../stories/STORY-030-docker-image-and-compose.md): Docker
  image (release) and `compose.yaml`, with the game files mounted, not
  baked in.
