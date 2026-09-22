# Mirror Codex — Tile Bit Flag Inspector + Flip Experiment Mode

## Goal
Add a simple, fast way to **toggle bit flags for a single tile** (and optionally paint them) to reverse-engineer unknown u8 layers (especially Terrain Flags).

This enables a workflow like:
- “Value is 1 (???). What happens if I flip it to 0?”
- “Which bit controls roads/rivers/corruption?”

---

## Scope
Applies to any **u8-per-tile layer**:
- Terrain Flags (primary)
- Minerals
- Exploration
- Landmass

Do NOT apply to Terrain(u16) directly (unless split into u8 sublayers).

---

## UI Requirements (Minimal)

### 1) Tile Inspector Panel
When a tile is hovered/clicked, show:
- Tile coords (x,y)
- Current value:
  - decimal (0–255)
  - hex (0x00–0xFF)
- Bit toggles:
  - Bits 0..7 as checkboxes/toggles
  - Each toggle updates the tile immediately

### 2) One-Click Experiment Controls
Buttons:
- **Set 0** (value = 0)
- **Set 255** (value = 255)
- **Invert** (value = value XOR 0xFF)
- **Revert Tile** (restore original value from load)

Optional (nice):
- **Snapshot A** (store current value)
- **Restore A** (restore stored value)

### 3) Bit Naming Integration
Reuse the existing “Bit Names” system:
- Allow assigning a name to bit 0..7 for the active layer
- Persist to stats DB (DETS) the same way as existing bit labels

---

## Interaction Rules

### Bit Toggle Math
When user toggles bit `b`:
- `new = old XOR (1 <<< b)`

When user clicks Set/Clear bit explicitly:
- Set: `new = old OR (1 <<< b)`
- Clear: `new = old AND bnot(1 <<< b)`

### Apply Immediately + Undoable
Every change must:
- be applied immediately to the in-memory layer
- emit a canvas patch for that tile
- push onto undo stack (one action per click)

For drag paint (optional):
- rate-limit patches
- treat one drag as a single undo “stroke”

---

## Safety Rails
- All toggles are undoable
- Revert Tile restores from the session’s original loaded layer bytes
- If no save loaded, disable inspector

---

## Validation
- Flipping a bit changes the tile value correctly (decimal/hex match)
- Terrain Flags flips are visible in render mode where applicable
- Undo/redo works for bit flips
- Revert Tile restores exact original value

---

End of document.
