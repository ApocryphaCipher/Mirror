import test from "node:test"
import assert from "node:assert/strict"
import {
  animatedCells,
  isAnimatedTile,
  shouldAdvance,
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

test("the clock ticks at once, then every interval", () => {
  assert.equal(shouldAdvance(1000, null, 160), true)
  assert.equal(shouldAdvance(1100, 1000, 160), false)
  assert.equal(shouldAdvance(1160, 1000, 160), true)
  assert.equal(shouldAdvance(5000, 1000, 160), true)
})

test("a clock that went backwards ticks instead of freezing", () => {
  assert.equal(shouldAdvance(500, 1000, 160), true)
})
