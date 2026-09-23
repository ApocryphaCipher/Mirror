# Backlog

Unsorted, not yet promoted to a story.

- ~~Cross-check `Mirror.Quality.ShoreMask` mask math against the MOMIME Java
  source~~ — done, see [epics/EPIC-001-terrain-rendering.md](epics/EPIC-001-terrain-rendering.md) and
  [notes/2026-09-22-momime-source-findings.md](notes/2026-09-22-momime-source-findings.md). Now it's an
  implementation task, not a research task.
- Decide raw-LBX vs MOMIME-PNG as the primary asset path (see EPIC-001) —
  right now both are half-built and neither is documented as "the" path.
  Doesn't block fixing the bitmask math itself, which is shared by both
  paths.
- `MIRROR_TERRAIN_OFFSET` etc. offsets are currently only set in
  `scripts/dev_server.sh`, sourced from a community wiki rather than
  anything Kevin/Gemini derived themselves — worth a sanity pass (e.g.
  cross-check city/unit counts from the loaded save against what the game
  itself reports) before fully trusting them for anything beyond terrain.
- `lib/mirror/map.ex` and related bitstring-match warnings on Elixir 1.20
  (pin operator, `0..@width - 1` guard step) — harmless today, cheap cleanup
  whenever someone's in that file.
- `mix tailwind mirror` (and running `_build/tailwind-macos-arm64` directly)
  crashes with SIGKILL (exit 137), reproducibly, in this dev environment —
  matching crash reports in `~/Library/Logs/DiagnosticReports/`. Found while
  building PR #5's tile-probe UI; worked around with inline `style=`
  attributes on the handful of new utility classes instead of fixing the
  build. Means any *other* new Tailwind class added elsewhere won't render
  until this is actually fixed — worth root-causing (looked like it might be
  a macOS Gatekeeper/quarantine issue on the downloaded arm64 binary, not
  confirmed) rather than continuing to route around it file by file.
