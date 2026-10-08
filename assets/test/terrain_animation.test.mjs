import test from "node:test"
import assert from "node:assert/strict"
import {
  ANIMATION_INTERVAL_MS,
  ANIMATION_STORAGE_KEY,
  animatedCells,
  isAnimatedTile,
  loadAnimationPreference,
  phaseAt,
  saveAnimationPreference,
  updateAnimatedCell,
} from "../js/terrain_animation.mjs"

// tile number -> [first frame index, frame count]; -1 is a tile with no art.
const tiles = {0: [0, 1], 31: [31, 4], 601: [601, 4], 18: [18, 4], 77: [-1, 4]}

test("a tile with more than one frame is animated; a still or missing one is not", () => {
  assert.equal(isAnimatedTile(tiles, 601), true)
  assert.equal(isAnimatedTile(tiles, 0), false)
  assert.equal(isAnimatedTile(tiles, 12345), false)
  assert.equal(isAnimatedTile(undefined, 601), false)
})

test("a tile with no art is not animated even if it lists frames", () => {
  assert.equal(isAnimatedTile(tiles, 77), false)
})

test("animatedCells lists only the cells holding animated tiles", () => {
  const values = Uint16Array.from([0, 601, 0, 31, 0, 0, 18, 999])
  assert.deepEqual([...animatedCells(values, tiles)].sort((a, b) => a - b), [1, 3, 6])
})

test("animatedCells is empty without values or atlas data", () => {
  assert.equal(animatedCells(null, tiles).size, 0)
  assert.equal(animatedCells(Uint16Array.from([601]), undefined).size, 0)
})

test("painting an animated tile adds the cell, painting over it removes it", () => {
  const cells = new Set()
  assert.equal(updateAnimatedCell(cells, 5, tiles, 601), true)
  assert.deepEqual([...cells], [5])
  assert.equal(updateAnimatedCell(cells, 5, tiles, 601), false)
  assert.equal(updateAnimatedCell(cells, 5, tiles, 0), true)
  assert.equal(cells.size, 0)
  assert.equal(updateAnimatedCell(cells, 5, tiles, 0), false)
})

test("an animated tile changing to another animated tile keeps the cell", () => {
  const cells = new Set([2])
  assert.equal(updateAnimatedCell(cells, 2, tiles, 31), false)
  assert.deepEqual([...cells], [2])
})

test("the step is the game's, about 0.6 s", () => {
  assert.equal(ANIMATION_INTERVAL_MS, 600)
})

test("a timestamp falls in a step, and a step lasts one interval", () => {
  assert.equal(phaseAt(0), 0)
  assert.equal(phaseAt(599), 0)
  assert.equal(phaseAt(600), 1)
  assert.equal(phaseAt(1250), 2)
  assert.equal(phaseAt(1250, 100), 12)
})

test("two clocks asked about the same moment give the same step", () => {
  // The terrain canvas and the overlay canvas each ask; they must agree.
  for (const now of [0, 1, 599, 600, 123456.789, 9e6]) {
    assert.equal(phaseAt(now), phaseAt(now))
  }
  assert.equal(phaseAt(123456.789), Math.floor(123456.789 / 600))
})

test("a clock that was backgrounded for a while lands on the right step at once", () => {
  assert.equal(phaseAt(60_000), 100)
})

const fakeStorage = (initial = {}) => {
  const data = {...initial}
  return {getItem: key => data[key] ?? null, setItem: (key, value) => (data[key] = String(value)), data}
}

test("the animation choice defaults on, off for reduced motion, and a stored choice wins", () => {
  assert.equal(loadAnimationPreference(fakeStorage(), false), true)
  assert.equal(loadAnimationPreference(fakeStorage(), true), false)
  assert.equal(loadAnimationPreference(fakeStorage({[ANIMATION_STORAGE_KEY]: "0"}), false), false)
  assert.equal(loadAnimationPreference(fakeStorage({[ANIMATION_STORAGE_KEY]: "1"}), true), true)
})

test("storage that is missing or throws falls back to the default", () => {
  const throwing = {
    getItem() {
      throw new Error("blocked")
    },
    setItem() {
      throw new Error("blocked")
    },
  }
  assert.equal(loadAnimationPreference(null, false), true)
  assert.equal(loadAnimationPreference(throwing, false), true)
  assert.equal(loadAnimationPreference(throwing, true), false)
  assert.doesNotThrow(() => saveAnimationPreference(throwing, true))
  assert.doesNotThrow(() => saveAnimationPreference(null, true))
})

test("the choice is stored as 1 or 0 and read back", () => {
  const storage = fakeStorage()
  saveAnimationPreference(storage, false)
  assert.equal(storage.data[ANIMATION_STORAGE_KEY], "0")
  assert.equal(loadAnimationPreference(storage, false), false)
  saveAnimationPreference(storage, true)
  assert.equal(loadAnimationPreference(storage, true), true)
})
