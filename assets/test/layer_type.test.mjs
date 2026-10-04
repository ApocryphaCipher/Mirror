import test from "node:test"
import assert from "node:assert/strict"
import {layerTypeAfterDelta} from "../js/layer_type.mjs"

test("a delta for the active layer sets its type", () => {
  assert.equal(layerTypeAfterDelta("u8", "terrain", "terrain", "u16"), "u16")
  assert.equal(layerTypeAfterDelta("u16", "landmass", "landmass", "u8"), "u8")
})

test("a delta for another layer leaves the active layer's type alone", () => {
  assert.equal(layerTypeAfterDelta("u16", "terrain", "landmass", "u8"), "u16")
  assert.equal(layerTypeAfterDelta("u8", "landmass", "terrain", "u16"), "u8")
})

test("a payload with no layer is for the active layer", () => {
  assert.equal(layerTypeAfterDelta("u8", "terrain", undefined, "u16"), "u16")
})

test("a payload with no type changes nothing", () => {
  assert.equal(layerTypeAfterDelta("u16", "terrain", "terrain", undefined), "u16")
})

// The sequence a painted type pushes: terrain first, then landmass. Terrain is the
// active layer, so the canvas must still draw it as u16 afterwards.
test("a terrain-then-landmass step leaves an active terrain layer as u16", () => {
  let type = "u16"
  for (const [layer, payloadType] of [["terrain", "u16"], ["landmass", "u8"]]) {
    type = layerTypeAfterDelta(type, "terrain", layer, payloadType)
  }
  assert.equal(type, "u16")
})
