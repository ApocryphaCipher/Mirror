# Backlog

Unsorted, not yet promoted to a story.

- ~~Cross-check `Mirror.Quality.ShoreMask` mask math against the MOMIME Java
  source~~ — done, see [epics/EPIC-001-terrain-rendering.md](epics/EPIC-001-terrain-rendering.md) and
  [notes/2026-09-22-momime-source-findings.md](notes/2026-09-22-momime-source-findings.md). Now it's an
  implementation task, not a research task.
- ~~Decide raw-LBX vs MOMIME-PNG as the primary asset path~~ — decided
  2026-09-22: raw `TERRAIN.LBX`. See
  [reference/classic-terrain-format.md](reference/classic-terrain-format.md) and STORY-005.
- ~~Pull the rest of the GOG install down~~ → promoted to STORY-006.
- Check whether the `FONTS.LBX` entry-2 palette also fixes
  `Mirror.LBX.Palette`'s `:auto` mode for non-terrain LBX files (the old
  "colored noise" bug).
- Decode `TERRTYPE.LBX` properly (the original game's mask → tile table).
  Only needed if Mirror ever edits terrain.
- `MIRROR_TERRAIN_OFFSET` etc. offsets are currently only set in
  `scripts/dev_server.sh`, sourced from a community wiki rather than
  anything Kevin/Gemini derived themselves — worth a sanity pass (e.g.
  cross-check city/unit counts from the loaded save against what the game
  itself reports) before fully trusting them for anything beyond terrain.
- `lib/mirror/map.ex` and related bitstring-match warnings on Elixir 1.20
  (pin operator, `0..@width - 1` guard step) — harmless today, cheap cleanup
  whenever someone's in that file.
- ~~`mix tailwind mirror` crashes with SIGKILL (exit 137)~~ — fixed
  2026-09-22. Root cause: Tailwind's standalone macOS binary (a Bun-compiled
  executable) ships with an invalid ad-hoc code signature. We checked it is
  byte-identical to the official release, so it's upstream, not tampering.
  macOS 27 enforces signatures page by page and kills it ("Code Signature
  Invalid"). Still broken upstream in tailwindcss v4.3.3 and not handled by
  the tailwind hex package (v0.5.1). The `assets.*` aliases in `mix.exs`
  now re-sign the binary ad-hoc when verification fails. PR #5's inline
  `style=` workarounds were replaced with real classes.
- ~~Remove the MOMIME-PNG render path~~ — done 2026-09-22 with STORY-014.
  Deleted `MomimePngIndex`, `Quality.ShoreMask` (+ tests, fixture,
  `shore_metrics.exs`), `build_momime_resources_index.sh`, the
  `MIRROR_TILE_BACKEND` switch, the tagged-LBX atlas fallback, and ~2,000
  lines of client-side MOMIME/shore/kind code. `Quality.SmoothingRules`
  is kept (standalone, tested) as a possible cross-check for STORY-017.
- `/tile-probe`'s "Label tile" tagging (writes `priv/asset_map/*.json`
  via `AssetMap`) no longer feeds rendering. Decide in STORY-006 whether
  to repurpose it for the sprite catalog or delete it.
- ~~App renders with no CSS at all~~ — same root cause as above, fixed.
- Draw tiles at native 20×18 aspect instead of stretched into square cells
  (canvas geometry change; see `Canvas_Geometry_Invariants` in codex-notes).
