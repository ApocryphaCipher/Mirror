# STORY-042: Docs truth pass

**Parent:** [EPIC-008](../epics/EPIC-008-keeping-the-lights-on.md)
**Status:** **Done** (2026-09-26)
**Size:** small to medium (docs only)

The [review note](../notes/2026-09-24-ktlo-review.md#documentation-review-docs-versus-code)
lists 26 places where the docs no longer match the code. Fix them in one
docs PR, grouped as follows:

- **README:** cities, layer toggles, the Surveyor and fog now exist.
  Units, sites, roads and auras don't yet.
- **Epic and story statuses:**
  - EPIC-002 (MOMIME removal) is done.
  - EPIC-006 is in progress, not "not started".
  - EPIC-004's current-state section and its city `+34` field are wrong.
  - EPIC-005 and STORY-008 still say auras are realm-coloured; they're
    owner-coloured.
  - The stories index lacks Done marks for 014, 015, 016, 023, 026 and
    027.
  - STORY-015 and STORY-016 describe controls and deferrals that have
    changed.
  - STORY-010 has a stale sprite note.
- **surveyor-formula.md:**
  - The empty-site wild-game wording contradicts itself: the table says
    1 quarter-food, the prose says 2.
  - Nodes take precedence over sites, not the other way round.
  - A city's own tile shows City Resources only after the
    water/tower/node/lair checks.
  - Mirror shows an "Unexplored" card where the game shows nothing.
- **STORY-035 and STORY-036:**
  - Discard (STORY-039) is wrong in STORY-035's outcome.
  - Fog does cover the cities and the tint.
  - A tinted tile's max pop can differ from the Surveyor card's: the
    overlay counts fog as explored, and the card doesn't.
- **Old notes:** 2026-09-22 (recon, MOMIME findings), 2026-09-23 evening
  handoff and 2026-09-24 live-RAM evaluation. Add "superseded" notices
  that link to the newer notes, and point `docs/README.md` at the
  current handoff.
- **Backlog:**
  - The TERRTYPE item duplicates STORY-017.
  - The tile-probe tagging decision belongs in its own item, not closed
    STORY-006.
  - Re-running the import doesn't copy the extra LBX files.

## Outcome (2026-09-26)

All 26 docs findings from the review note were verified and resolved:
- **README & AGENTS.md:** Updated Status to include cities, layer toggles,
  Surveyor readout, and fog; documented `MIRROR_SURVEYOR_SAVE` alongside
  `MIRROR_MOM_PATH`; updated AGENTS.md with universal `SaveFile.write/3` original
  protection, 9-slot limits, and the raw editor's landmass consistency limitation.
- **Epics & stories:** Marked EPIC-002 Done and framed its "today" text as
  historical; marked EPIC-006 in progress; corrected EPIC-004's status, historical
  scope, and city block offsets (`+31..+66` buildings, `+67..+92` enchantments);
  reconciled EPIC-005 and STORY-008 to owner banner colors for melded nodes;
  synchronized completion marks in the stories index; updated STORY-010 with
  STORY-032's outcome; updated STORY-015 deferred list and STORY-016 mouse
  controls (Cycle vs Paint).
- **surveyor-formula.md:** Reconciled empty-site wild game prose with the 1
  quarter-food implementation; listed nodes before sites in feature checks;
  qualified the existing-city settle check precedence; documented Mirror's
  "Unexplored" placeholder card.
- **STORY-035 & STORY-036:** Documented that settleable overlay treats the map as
  explored while Surveyor respects fog; noted the Discard overlay refresh gap
  (STORY-039); clarified visual fog layering over cities and settlement tint.
- **Notes & index:** Added prominent historical/superseded notices to 2026-09-22
  recon and MOMIME notes, 2026-09-23 evening handoff, and 2026-09-24 live RAM
  evaluation; pointed `docs/README.md` at the latest handoffs.
- **Backlog:** Clarified extra LBX exploration; linked TERRTYPE to STORY-017
  auto-tiling; detached tile-probe tagging decision from closed STORY-006.

## Done when

Every docs finding in the note is fixed, or marked with the reason it was
left.
