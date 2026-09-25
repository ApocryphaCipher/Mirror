# EPIC-008: Keeping the Lights On

**Status:** open (review done 2026-09-24)
**Requested by:** [Kevin](https://github.com/KevinAsbury), 2026-09-24

## Goal

Pay down what a full review of `main` found: bugs, save-safety gaps, bad
input handling, missing CI coverage, and docs that no longer tell the
truth. No new features. Work through the stories in priority order; each
is small enough for one PR.

The source is [the review note](../notes/2026-09-24-ktlo-review.md): 25
code findings and 26 docs findings from two read-only reviews by OpenAI
Codex, triaged by Claude. Each finding says how it was checked. Re-check
a finding before fixing it, and add a test that fails without the fix
(AGENTS.md §10).

## Stories, in priority order

1. [STORY-038](../stories/STORY-038-save-as-safety.md) **P1 bug:** Save as
   can overwrite the loaded save, and other save-safety gaps. **Fix
   first.**
2. [STORY-039](../stories/STORY-039-edit-state-consistency.md) P2: the
   editor's state gets out of step (discard, undo/redo, two tabs, engine
   sessions).
3. [STORY-040](../stories/STORY-040-decoder-robustness.md) P2: decoders
   that raise, or accept malformed data, on bad input.
4. [STORY-041](../stories/STORY-041-edit-tests-in-ci.md) P2: editing and
   save-safety tests are all skipped in CI.
5. [STORY-042](../stories/STORY-042-docs-truth-pass.md) P2: a docs pass
   (README, epics and story statuses, the Surveyor doc, old notes).
6. [STORY-043](../stories/STORY-043-maintainability.md) P3: `map_live.ex`
   (3,400 lines) and dead code.

Already covered elsewhere, so not duplicated: terrain edits don't keep
the landmass (continent) IDs consistent. That's
[STORY-017](../stories/STORY-017-terrain-editing-autotile.md) and
[STORY-029](../stories/STORY-029-safe-editing-see-everything.md), but
STORY-041's docs fix should say plainly that today's editor doesn't do it.
