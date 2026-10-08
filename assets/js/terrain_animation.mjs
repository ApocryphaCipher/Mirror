// Pure helpers for the map animations (STORY-007, 008): which map cells hold an
// animated TERRAIN.LBX tile, the shared clock, and the "Animate terrain" choice.
//
// `planeTiles` is the atlas's list for one plane: tile number -> [first frame's
// index, frame count], or [-1, ...] for a tile with no art. A tile with more than
// one frame is animated (601, the twinkling ocean, is the common one).

// One animation step: the real game steps its overland animation (the ocean, the
// node tiles and the node sparkles alike) about every 0.6 s, measured from DOSBox
// screenshots on 2026-10-07 (a 601 ocean tile: 4 looks, one every 0.56-0.68 s).
export const ANIMATION_INTERVAL_MS = 600

export const ANIMATION_STORAGE_KEY = "mirror.animateTerrain"

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

// Whether a "roads" overlay's items include an enchanted road, the only road art that
// animates. (The layer also carries specials and corruption, which do not.)
export function hasEnchantedRoad(items) {
  return Array.isArray(items) && items.some(item => item.kind === "road" && item.enchanted)
}

// The animation step a timestamp falls in. Everything that animates (the terrain
// canvas and the overlay canvas) takes its frame from this, so they stay in step
// without sharing a timer, and a throttled or backgrounded tab catches up at once.
export function phaseAt(now, intervalMs = ANIMATION_INTERVAL_MS) {
  return Math.floor(now / intervalMs)
}

// The remembered "Animate terrain" choice. Without one, it is on unless the
// system asks for reduced motion. `storage` and `prefersReducedMotion` are passed in
// so this can be tested; storage can be blocked or throw, which falls back to the
// default.
export function loadAnimationPreference(storage, prefersReducedMotion) {
  try {
    const stored = storage?.getItem(ANIMATION_STORAGE_KEY)
    if (stored === "1") return true
    if (stored === "0") return false
  } catch (_error) {
    // fall through to the default
  }
  return !prefersReducedMotion
}

export function saveAnimationPreference(storage, enabled) {
  try {
    storage?.setItem(ANIMATION_STORAGE_KEY, enabled ? "1" : "0")
  } catch (_error) {
    // not remembered, still applied
  }
}
