import test from "node:test"
import assert from "node:assert/strict"
import {OVERLAY_DRAWERS} from "../js/map_overlays.js"

// A canvas context that only records drawImage, and a sprite bank that records which
// image was asked for.
function harness(sparkles = {yellow: {width: 20, height: 18, frames: [0, 1, 2, 3, 4, 5]}}) {
  const drawn = []
  const asked = []
  const ctx = {drawImage: (image, left, top, w, h) => drawn.push({image, left, top, w, h})}
  const sprites = {
    sparkles,
    image(name, sprite, frame, banner) {
      asked.push({name, frame, banner})
      return `${name}#${frame}`
    },
  }
  return {ctx, sprites, drawn, asked}
}

test("auras: one sparkle per aura tile, centred on its tile", () => {
  const {ctx, sprites, drawn} = harness()
  OVERLAY_DRAWERS.auras(
    ctx,
    [
      {x: 42, y: 10, banner: "yellow"},
      {x: 43, y: 10, banner: "yellow"},
    ],
    {tileSize: 20, sprites, phase: 0}
  )

  assert.equal(drawn.length, 2)
  // The 20x18 art scales per axis to fill the square map cell, like every overlay.
  assert.deepEqual(drawn[0], {image: "sparkles.yellow#0", left: 42 * 20, top: 10 * 20, w: 20, h: 20})
  assert.equal(drawn[1].left, 43 * 20)
})

test("auras: the frame follows the shared step, wrapping over the sprite's six frames", () => {
  for (const [phase, frame] of [[0, 0], [1, 1], [5, 5], [6, 0], [13, 1]]) {
    const {ctx, sprites, asked} = harness()
    OVERLAY_DRAWERS.auras(ctx, [{x: 1, y: 1, banner: "yellow", i: 0}], {tileSize: 20, sprites, phase})
    assert.equal(asked[0].frame, frame, `phase ${phase}`)
  }
})

test("auras: tile i shows frame (step + i) mod 6, so the field ripples", () => {
  // What DOSBox showed for the eight tiles of a Chaos node's aura at one moment:
  // frames 4, 5, 0, 1, 2, 3, 4, 5 in aura-list order.
  const {ctx, sprites, asked} = harness()
  const items = Array.from({length: 8}, (_, i) => ({x: i, y: 0, banner: "yellow", i}))
  OVERLAY_DRAWERS.auras(ctx, items, {tileSize: 20, sprites, phase: 4})
  assert.deepEqual(asked.map(a => a.frame), [4, 5, 0, 1, 2, 3, 4, 5])
})

test("auras: a step later, every tile has moved on by one", () => {
  const {ctx, sprites, asked} = harness()
  const items = Array.from({length: 8}, (_, i) => ({x: i, y: 0, banner: "yellow", i}))
  OVERLAY_DRAWERS.auras(ctx, items, {tileSize: 20, sprites, phase: 5})
  assert.deepEqual(asked.map(a => a.frame), [5, 0, 1, 2, 3, 4, 5, 0])
})

test("auras: with animation off (no phase) the sparkles hold their still pattern", () => {
  const {ctx, sprites, asked} = harness()
  const items = [0, 1, 2].map(i => ({x: i, y: 1, banner: "yellow", i}))
  OVERLAY_DRAWERS.auras(ctx, items, {tileSize: 20, sprites})
  assert.deepEqual(asked.map(a => a.frame), [0, 1, 2])
})

test("auras: an item without a list position counts as the first tile", () => {
  const {ctx, sprites, asked} = harness()
  OVERLAY_DRAWERS.auras(ctx, [{x: 1, y: 1, banner: "yellow"}], {tileSize: 20, sprites, phase: 2})
  assert.equal(asked[0].frame, 2)
})

test("auras: sparkles are drawn in their own colours, never recoloured as a banner", () => {
  const {ctx, sprites, asked} = harness()
  OVERLAY_DRAWERS.auras(ctx, [{x: 1, y: 1, banner: "yellow"}], {tileSize: 20, sprites, phase: 0})
  // `false` is the bank's "no remap" (the green entry uses the flag colours 216-218,
  // which a banner remap would turn brown).
  assert.equal(asked[0].banner, false)
})

test("auras: each owner's tiles use that owner's sparkle entry", () => {
  const entry = {width: 20, height: 18, frames: [0, 1, 2, 3, 4, 5]}
  const {ctx, sprites, asked} = harness({yellow: entry, green: entry})
  OVERLAY_DRAWERS.auras(
    ctx,
    [
      {x: 1, y: 1, banner: "yellow"},
      {x: 2, y: 2, banner: "green"},
    ],
    {tileSize: 20, sprites, phase: 0}
  )
  assert.deepEqual(asked.map(a => a.name), ["sparkles.yellow", "sparkles.green"])
})

test("auras: a banner with no sparkle art is skipped, not drawn wrong", () => {
  const {ctx, sprites, drawn} = harness()
  OVERLAY_DRAWERS.auras(ctx, [{x: 1, y: 1, banner: "neutral"}], {tileSize: 20, sprites, phase: 0})
  assert.equal(drawn.length, 0)
})

test("auras: draws nothing before the sprites arrive", () => {
  const {ctx, drawn} = harness()
  OVERLAY_DRAWERS.auras(ctx, [{x: 1, y: 1, banner: "yellow"}], {tileSize: 20, sprites: null})
  OVERLAY_DRAWERS.auras(ctx, [{x: 1, y: 1, banner: "yellow"}], {tileSize: 20, sprites: {}})
  assert.equal(drawn.length, 0)
})

test("auras: scales with the tile size", () => {
  const {ctx, sprites, drawn} = harness()
  OVERLAY_DRAWERS.auras(ctx, [{x: 2, y: 3, banner: "yellow"}], {tileSize: 40, sprites, phase: 0})
  assert.equal(drawn[0].w, 40)
  assert.equal(drawn[0].h, 40)
  assert.equal(drawn[0].left, 2 * 40)
})

// --- roads (STORY-045) ---
function roadHarness() {
  const piece = {width: 20, height: 18, frames: [0, 1, 2, 3, 4, 5]}
  const asked = []
  const ctx = {drawImage: () => {}}
  const sprites = {
    roads: {c: {...piece, frames: [0]}, ne: {...piece, frames: [0]}},
    enchanted_roads: {c: piece, ne: piece},
    specials: {gold: {width: 20, height: 18, frames: [0]}},
    image(name, sprite, frame, banner) {
      asked.push({name, frame, banner})
      return `${name}#${frame}`
    },
  }
  return {ctx, sprites, asked}
}

test("roads: an enchanted road's pieces all show frame (step mod 6)", () => {
  for (const [phase, frame] of [[0, 0], [1, 1], [3, 3], [5, 5], [6, 0], [10, 4]]) {
    const {ctx, sprites, asked} = roadHarness()
    const item = {kind: "road", x: 4, y: 4, pieces: ["c", "ne"], enchanted: true}
    OVERLAY_DRAWERS.roads(ctx, [item], {tileSize: 20, sprites, phase})
    assert.deepEqual(
      asked.map(a => [a.name, a.frame]),
      [["enchanted_roads.c", frame], ["enchanted_roads.ne", frame]],
      `phase ${phase}`
    )
  }
})

test("roads: every enchanted tile is on the same frame, with no per-tile offset", () => {
  // The game shows one frame across a whole enchanted road (unlike the node sparkles).
  const {ctx, sprites, asked} = roadHarness()
  const items = [0, 1, 2, 3].map(i => ({kind: "road", x: i, y: 2, pieces: ["c"], enchanted: true}))
  OVERLAY_DRAWERS.roads(ctx, items, {tileSize: 20, sprites, phase: 3})
  assert.deepEqual(asked.map(a => a.frame), [3, 3, 3, 3])
})

test("roads: a plain road never animates", () => {
  for (const phase of [0, 1, 2, 3, 7]) {
    const {ctx, sprites, asked} = roadHarness()
    OVERLAY_DRAWERS.roads(
      ctx,
      [{kind: "road", x: 4, y: 4, pieces: ["c", "ne"], enchanted: false}],
      {tileSize: 20, sprites, phase}
    )
    assert.deepEqual(asked.map(a => [a.name, a.frame]), [["roads.c", 0], ["roads.ne", 0]])
  }
})

test("roads: with animation off (no phase) an enchanted road holds frame 0, today's picture", () => {
  const {ctx, sprites, asked} = roadHarness()
  OVERLAY_DRAWERS.roads(
    ctx,
    [{kind: "road", x: 4, y: 4, pieces: ["c"], enchanted: true}],
    {tileSize: 20, sprites}
  )
  assert.equal(asked[0].frame, 0)
})

test("roads: specials still draw their one frame while enchanted roads step", () => {
  const {ctx, sprites, asked} = roadHarness()
  OVERLAY_DRAWERS.roads(
    ctx,
    [
      {kind: "special", x: 1, y: 1, special: "gold"},
      {kind: "road", x: 2, y: 2, pieces: ["c"], enchanted: true},
    ],
    {tileSize: 20, sprites, phase: 4}
  )
  assert.deepEqual(asked.map(a => [a.name, a.frame]), [["specials.gold", 0], ["enchanted_roads.c", 4]])
})
