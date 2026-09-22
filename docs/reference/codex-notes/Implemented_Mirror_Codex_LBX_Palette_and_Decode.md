# Mirror — LBX Palette & Tile Decode Fix (Codex Prompt)

This document explains **why tiles render black & white** and **why tiles appear as rectangles or half‑tiles**, and defines the **required decoding rules** for LBX images in Mirror.

Paste this file directly into Codex as an instruction.  
Do **not** change architecture or UX — this is a decode correctness fix.

---

## Problem Summary

Mirror correctly:
- discovers LBX files automatically from `MIRROR_MOM_PATH`
- reads LBX containers and image entries
- renders tiles (not per‑pixel drawing)

Two issues remain:
1. Tiles are black & white
2. Tiles appear as rectangles or “cut in half”

These are **palette application** and **scanline decode** issues.

---

## 1. Palette Handling (Why Tiles Are Black & White)

LBX image data is **8‑bit indexed color**, not RGB.

Current behavior:
- Pixel index values are rendered as grayscale intensity.

Correct behavior:
- Pixel index → palette lookup → RGB color.

### Required Palette Logic

For each LBX image entry:

1. Decode pixel data as **palette indices**.
2. Determine palette source:
   - Some entries embed a palette.
   - Some entries inherit a palette from another entry.
   - If no embedded palette exists, use the default palette for that LBX file.
3. Convert palette values to RGB:
   - DOS VGA palettes typically store channels in **0–63**.
   - Scale to 0–255:
     ```
     rgb = round(v * 255 / 63)
     ```
4. Produce RGBA output:
   - alpha = 255 unless a known transparent index exists.

### Validation

After applying palette:
- Water tiles appear blue
- Grass/forest appear green
- Desert appears yellow/brown
- Mountains appear gray/brown

If tiles are very dark → palette scaling is missing.

---

## 2. Tile Shape Errors (Rectangles / Half‑Tiles)

This indicates **incorrect RLE decode layout**, not bad image data.

### Common Root Causes

#### A) Width Misinterpretation
After decode:
```
decoded_pixel_count MUST equal width * height
```

If not:
- Width or height is misread (endianness or meaning)
- Or RLE decode is incorrect

#### B) RLE Runs Crossing Scanlines (Most Common)

LBX RLE encoding does **not** guarantee runs stop at row boundaries.

Incorrect assumption:
- One RLE run fits entirely in the current row.

Correct behavior:
- Runs must be clamped to row width and continue on the next row.

### Required RLE Emission Logic

Maintain `(x, y)` cursor:

```
while run_length > 0:
  writable = min(run_length, width - x)
  write writable pixels at (x, y)
  x += writable
  run_length -= writable

  if x == width:
    x = 0
    y += 1
```

Stop decoding **exactly** when:
```
y == height
```

Do not assume runs align to rows.

This fix resolves:
- half tiles
- stretched rectangles
- diagonal tearing artifacts

---

## 3. Mandatory Assertions

After decoding an image entry:

- Assert:
  ```
  pixel_count == width * height
  ```
- Width/height must be read **little‑endian**
- No implicit row padding unless explicitly documented

If assertions fail, image record parsing is incorrect.

---

## 4. Design Constraints (Do Not Change)

- No user‑supplied LBX path.
- LBX files are auto‑discovered from `MIRROR_MOM_PATH`.
- Tile labeling / mapping is **not required** to render tiles.
- Placeholder tile selection is acceptable.
- Decode correctness is mandatory.

---

## One‑Line Diagnosis

“The renderer is correct; the issue is palette application and scanline‑aware RLE decoding. Apply palette lookup and clamp RLE runs to scanlines.”

---

End of document.
