# STORY-042: Docs truth pass

**Parent:** [EPIC-008](../epics/EPIC-008-keeping-the-lights-on.md)
**Status:** open, P2
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

## Done when

Every docs finding in the note is fixed, or marked with the reason it was
left.
