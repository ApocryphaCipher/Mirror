import test from "node:test"
import assert from "node:assert/strict"
import {tileAtViewportPoint} from "../js/view_click.mjs"

const base = {rect: {left: 100, top: 50}, tx: 0, ty: 0, scale: 1, tileSize: 12, mapWidth: 60, mapHeight: 40}

test("a point maps to the tile under it", () => {
  assert.deepEqual(tileAtViewportPoint({...base, clientX: 100, clientY: 50}), {x: 0, y: 0})
  assert.deepEqual(tileAtViewportPoint({...base, clientX: 100 + 12 * 7 + 5, clientY: 50 + 12 * 17 + 11}), {x: 7, y: 17})
})

test("zoom and pan shift the tile the same point lands on", () => {
  // scale 2: a tile is 24px; translated 30px right
  const view = {...base, scale: 2, tx: 30, ty: 0}
  assert.deepEqual(tileAtViewportPoint({...view, clientX: 100 + 30 + 24 * 3 + 1, clientY: 50 + 1}), {x: 3, y: 0})
})

test("outside the map is null", () => {
  assert.equal(tileAtViewportPoint({...base, clientX: 99, clientY: 60}), null)
  assert.equal(tileAtViewportPoint({...base, clientX: 100 + 12 * 60, clientY: 60}), null)
  assert.equal(tileAtViewportPoint({...base, clientX: 120, clientY: 50 + 12 * 40}), null)
})

test("a missing scale or tile size gives null, not NaN", () => {
  assert.equal(tileAtViewportPoint({...base, scale: 0, clientX: 120, clientY: 60}), null)
  assert.equal(tileAtViewportPoint({...base, tileSize: undefined, clientX: 120, clientY: 60}), null)
})
