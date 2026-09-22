# Mirror — Canvas Geometry & Tile Aspect Invariants (Codex Prompt)

This document defines **non-negotiable geometry rules** for rendering Master of Magic tiles in Mirror.
Its sole purpose is to prevent tile stretching, aspect drift, and misaligned coastlines.

Paste this file directly into Codex as an instruction.
Do not redesign UX or rendering architecture; enforce these invariants.

---

## Core Invariant

**Each map tile must always render as a perfect N×N square in device pixels.**
No CSS scaling, no accumulated transforms, no width/height divergence.

If this invariant breaks, all visual reasoning (coasts, overlays, adjacency) becomes invalid.

---

## Canvas Rules (Required)

### 1. Canvas Internal Size vs CSS Size

HTML canvas has two sizes:
- internal drawing buffer (`canvas.width`, `canvas.height`)
- CSS display size (`style.width`, `style.height`)

These MUST be kept in sync.

### Model A — Canvas Is the World (Simple)

Use when drawing the entire map at once.

- `canvas.width  = mapWidth * tileSize * dpr`
- `canvas.height = mapHeight * tileSize * dpr`
- `canvas.style.width  = (mapWidth * tileSize) + "px"`
- `canvas.style.height = (mapHeight * tileSize) + "px"`

Draw coordinates multiplied by `dpr`.

### Model B — Canvas Is a Viewport (Camera Model)

Use when panning/zooming.

- CSS size defines viewport size
- Internal buffer matches viewport × `dpr`
- Camera math selects which tiles to draw
- Tile draw size remains **square**

Do not mix Model A and Model B.

---

## 2. Transform Discipline

Before **every full redraw**, reset transforms:

```
ctx.setTransform(1, 0, 0, 1, 0, 0);
```

Never allow cumulative `scale()` or `translate()` effects.

---

## 3. Tile Draw Math (Single Scalar Rule)

Use exactly **one** tile size scalar.

For every tile:
- `dx = x * tileSize`
- `dy = y * tileSize`
- `dw = tileSize`
- `dh = tileSize`

No separate width/height.
No ratios.
No “fit to container.”

Source images may vary; destination must not.

---

## 4. Pixel Alignment

- All draw coordinates must be integer device pixels.
- Account for device pixel ratio (DPR).
- Avoid fractional coordinates to prevent blur and drift.

---

## 5. Forbidden Practices

Do NOT:
- rely on CSS scaling for zoom
- stretch canvas to fit parent without resizing buffer
- accumulate transforms between frames
- use non-square destination rectangles

Any of these WILL cause tile distortion.

---

## Debug Verification (Recommended)

Add a temporary grid overlay:
- draw grid lines every tile
- verify spacing is constant across entire map
- if tiles stretch over time, transforms or canvas sizing are wrong

---

## Summary

If tiles ever appear rectangular, stretched, or slowly distort:
- decode is fine
- palette is irrelevant
- geometry invariants are broken

Fix geometry before touching anything else.

---

End of document.
