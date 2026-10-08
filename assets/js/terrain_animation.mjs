// Pure helpers for the terrain animation (STORY-007): which map cells hold an
// animated TERRAIN.LBX tile, and when the clock should advance.
//
// `planeTiles` is the atlas's list for one plane: tile number -> [first frame's
// index, frame count], or [-1, ...] for a tile with no art. A tile with more than
// one frame is animated (601, the twinkling ocean, is the common one).

export function isAnimatedTile(planeTiles, value) {
  const tile = planeTiles?.[value]
  return !!tile && tile[0] >= 0 && tile[1] > 1
}

// The cells (as row-major indexes) whose terrain tile is animated.
export function animatedCells(values, planeTiles) {
  const cells = new Set()
  if (!values || !planeTiles) return cells
  for (let i = 0; i < values.length; i++) {
    if (isAnimatedTile(planeTiles, values[i])) cells.add(i)
  }
  return cells
}

// Keep the set in step with one edited cell. Returns true when the set changed.
export function updateAnimatedCell(cells, index, planeTiles, value) {
  const animated = isAnimatedTile(planeTiles, value)
  if (animated === cells.has(index)) return false
  if (animated) cells.add(index)
  else cells.delete(index)
  return true
}

// Whether enough time has passed since the last tick. `last` is null before the
// first one (which ticks at once). A clock that jumped backwards ticks too, rather
// than freezing until it catches up.
export function shouldAdvance(now, last, intervalMs) {
  if (last === null || last === undefined) return true
  const elapsed = now - last
  return elapsed >= intervalMs || elapsed < 0
}
