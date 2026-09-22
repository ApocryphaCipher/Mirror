# Mirror Codex — Shoreline Semantic Classifier

## Goal
Stabilize shoreline rendering by **classifying shoreline semantics**, not guessing tile art via over-aggressive fallback.

## Problem Summary
- Coast rotation is now correct.
- Remaining issue: *toothy / spiky shorelines*.
- Cause: adjacency masks are being canonicalized too aggressively, collapsing semantically distinct shore shapes into incorrect tiles.
- Ternary diagonal values (0/1/2) are meaningful and must not be blindly reduced.

## Observations
- Cardinal directions encode land/ocean clearly.
- Diagonals encode *corner semantics*:
  - `0` = water
  - `1` = diagonal water supported by both adjacent cardinals
  - `2` = diagonal water with only one supporting cardinal
- Reducing `2 → 1` too early destroys concave vs convex shoreline intent.

## Required Change
Introduce a **two-stage shoreline classifier**:

### Stage 1 — Semantic Classification
Classify each shore tile into one of:
- `straight_edge`
- `convex_corner`
- `concave_inlet`
- `peninsula`
- `island_tip`
- `channel`

This classification uses:
- Cardinal land count
- Diagonal `2` positions
- Cardinal–diagonal support relationships

### Stage 2 — Tile Selection
Only after classification:
- Generate candidate masks
- Allow *limited* diagonal relaxation **within the same semantic class**
- Never mix concave and convex classes

## Guardrails
- Never canonicalize diagonals before semantic classification
- Fallback search must be class-scoped
- Log when fallback crosses classes (this should be rare)

## Deliverables
- New `classify_shore_semantics(tile, neighbors)` function
- Replace current diagonal-reduction fallback
- Debug overlay showing semantic class per shore tile

## Success Criteria
- Smooth coastlines
- No saw-tooth edges
- Minimal fallback usage
- Visual parity with classic Master of Magic coastlines
